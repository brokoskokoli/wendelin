package app.wendelin

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import android.view.View
import android.view.ViewGroup
import androidx.lifecycle.Lifecycle
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The assistant overlay: a transparent window with its own Flutter engine running the Dart
 * entrypoint `assistantMain` (app/lib/main.dart), which draws the sheet over the lower part of
 * the screen. Started by [WendelinVoiceSession] via `startAssistantActivity`.
 *
 * Shows over the lock screen; the Dart side then asks to unlock first and shows nothing personal
 * (see ADR 0006). Leaving the overlay (home, screen off) closes it.
 */
class AssistantActivity : WendelinActivity() {

    // WP186, K148: Keep screen awake while the assistant overlay is active.
    private val screenOn = AssistantScreenOn(
        addFlags = { window.addFlags(it) },
        clearFlags = { window.clearFlags(it) },
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        // Arrived before the Flutter engine starts (that may take a while on a cold start).
        VoiceLog.i("overlay-create restored=${savedInstanceState != null}")
        lastArrival = SystemClock.elapsedRealtime()
        createdAt = lastArrival
        AssistantArrivals.arrived()
        super.onCreate(savedInstanceState)
        showPlaceholder()
        frameWatchdog.start()
        // Called by the wake word with the screen off: it has to come on (the device stays locked).
        if (intent?.getBooleanExtra(WendelinVoiceInteractionService.EXTRA_WAKE, false) == true &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1
        ) {
            setTurnScreenOn(true)
        }
        // Personal content: no screenshots, not visible in the app switcher.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        screenOn.acquire()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
        }
    }

    // Cold start: the engine needs a moment, show a native placeholder until the first frame.
    private var placeholder: View? = null

    private fun showPlaceholder() {
        val view = AssistantSplash.create(this)
        placeholder = view
        addContentView(
            view,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
    }

    private fun hidePlaceholder() {
        (placeholder?.parent as? ViewGroup)?.removeView(placeholder)
        placeholder = null
    }

    // WP145: spawned from the process-wide group, not a fresh engine per opening; destroyed with
    // the activity (an engine from provideFlutterEngine would otherwise outlive it).
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        EngineGroups.forActivity(this, "assistantMain", "overlay")

    // Held: the engine outlives the activity and is destroyed through the pool (EngineGroups).
    override fun shouldDestroyEngineWithHost(): Boolean = !engineHeld

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        VoiceLog.i("overlay-engine-ready after=${sinceCreate()}ms")
        super.configureFlutterEngine(flutterEngine)
        assistant?.onReleaseHost = { releaseHost() }
        assistant?.onTeardownDone = { teardownDone() }
    }

    // WP145: the overlay ends at once, but Dart may still free native objects for seconds (a
    // Whisper model that was loading). The activity finishes, the wake word listens again and a
    // new assist opens a new activity with a new engine; this engine stays headless until Dart
    // reports `teardownDone` or HOLD_MS ran out (EngineGroups).
    private var engineHeld = false
    private var heldEngine: FlutterEngine? = null
    private var engineCleaned = false
    private var teardownReported = false
    private var wakeNotified = false

    /** Dart closes the overlay: ends the activity now, keeps the engine. False if impossible. */
    private fun releaseHost(): Boolean {
        screenOn.release()
        if (engineHeld) return true
        val engine = flutterEngine ?: return false
        if (!EngineGroups.hold(engine)) return false
        engineHeld = true
        heldEngine = engine
        VoiceLog.i("overlay-release-host finishing=$isFinishing")
        notifyWakeService()
        if (!isFinishing) finish()
        return true
    }

    private fun teardownDone() {
        teardownReported = true
        VoiceLog.i("overlay-teardown-done cleaned=$engineCleaned")
        // Before the activity is detached the engine must stay; cleanUpFlutterEngine looks again.
        if (engineCleaned) heldEngine?.let { e -> handler.post { EngineGroups.release(e) } }
    }

    private fun notifyWakeService() {
        if (wakeNotified) return
        wakeNotified = true
        // The wake-word service listens again once the overlay is gone (WP50).
        WakeWordService.onOverlayClosed()
        VoiceLog.i("overlay-close-notified wake=onOverlayClosed")
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        super.cleanUpFlutterEngine(flutterEngine)
        val engine = heldEngine ?: return
        engineCleaned = true
        // Our channels are gone with the activity; Dart still reports through this one.
        MethodChannel(engine.dartExecutor.binaryMessenger, AssistantChannel.CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "teardownDone") {
                    VoiceLog.i("overlay-teardown-done cleaned=true late=true")
                    // Reply first, destroy after: else "FlutterJNI was detached" in the log.
                    result.success(null)
                    handler.post { EngineGroups.release(engine) }
                } else {
                    result.notImplemented()
                }
            }
        // The delegate still detaches the engine from the activity after this call: destroy later.
        // Also marks the engine detached for the 14 s timeout (EnginePool.cleanedUp).
        handler.post {
            if (teardownReported) EngineGroups.release(engine) else EngineGroups.cleanedUp(engine)
        }
    }

    override fun onFlutterUiDisplayed() {
        VoiceLog.i("overlay-first-frame after=${sinceCreate()}ms")
        frameWatchdog.stop()
        hidePlaceholder()
        super.onFlutterUiDisplayed()
    }

    // No first frame within 10 s: close instead of leaving the placeholder up.
    private val frameWatchdog = FirstFrameWatchdog(
        schedule = { delayMs, block ->
            val r = Runnable(block)
            window.decorView.postDelayed(r, delayMs)
            AssistantLauncher.Cancelable { window.decorView.removeCallbacks(r) }
        },
        finish = { if (!isFinishing) finish() },
        log = VoiceLog::i,
    )

    private fun sinceCreate(): Long = SystemClock.elapsedRealtime() - (createdAt ?: 0L)

    override fun getDartEntrypointFunctionName(): String = "assistantMain"

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    /** The assistant was invoked again while the overlay is open. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val retry = intent.getBooleanExtra(EXTRA_RETRY, false)
        val now = SystemClock.elapsedRealtime()
        val since = lastArrival?.let { now - it }
        val triggers = RetryFilter.triggers(retry, since)
        VoiceLog.i(
            "overlay-new-intent finishing=$isFinishing engine=${assistant != null} " +
                "retry=$retry trigger=$triggers",
        )
        lastArrival = now
        AssistantArrivals.arrived()
        // The late twin of the first start (cold start): no second request. Not while the
        // overlay closes: a new assist then opens a new activity.
        if (triggers && !isFinishing && !engineHeld) assistant?.trigger()
    }

    companion object {
        /** Intent extra: the session starts the overlay a second time (B10). */
        const val EXTRA_RETRY = "app.wendelin.assistant.retry"

        private val RECHECK_TOKEN = Any()
        private const val RECHECK_MARGIN_MS = 100L
    }

    // When the overlay last arrived (create or new intent), elapsed realtime.
    private var lastArrival: Long? = null
    private var createdAt: Long? = null

    override fun onDestroy() {
        screenOn.release()
        frameWatchdog.stop()
        handler.removeCallbacksAndMessages(null)
        hidePlaceholder()
        VoiceLog.i("overlay-destroy finishing=$isFinishing")
        if (isFinishing) notifyWakeService()
        super.onDestroy()
    }

    override fun onStop() {
        super.onStop()
        // The overlay belongs to the moment it was opened; it does not stay in the background.
        // Dart closes first (stops microphone, speech output, request), then finishes.
        if (isChangingConfigurations || isFinishing) return
        if (assistant?.unlocking == true) {
            // The keyguard transition: not leaving. But if the user really left (home) in this
            // time, the stop must not be lost: look again when the grace period is over.
            postStopRecheck()
            return
        }
        closeOverlay()
    }

    private val handler = Handler(Looper.getMainLooper())

    private fun postStopRecheck() {
        handler.removeCallbacksAndMessages(RECHECK_TOKEN)
        val delay = (assistant?.unlockingRemainingMs() ?: 0L) + RECHECK_MARGIN_MS
        handler.postAtTime(
            {
                if (isFinishing || isDestroyed) return@postAtTime
                when {
                    assistant?.unlocking == true -> postStopRecheck()
                    // Still stopped after the transition: the overlay was left.
                    !lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED) -> closeOverlay()
                }
            },
            RECHECK_TOKEN,
            SystemClock.uptimeMillis() + delay,
        )
    }

    private fun closeOverlay() {
        screenOn.release()
        val channel = assistant
        VoiceLog.i("overlay-stop engine=${channel != null}")
        if (channel == null) {
            finish()
        } else {
            channel.requestClose { how ->
                VoiceLog.i("overlay-close by=$how finishing=$isFinishing")
                // Dart did not release the host itself (no answer, error): do it, else finish.
                if (!releaseHost() && !isFinishing) finish()
            }
        }
    }
}
