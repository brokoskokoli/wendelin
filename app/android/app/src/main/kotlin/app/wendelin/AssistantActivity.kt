package app.wendelin

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode

/**
 * The assistant overlay: a transparent window with its own Flutter engine running the Dart
 * entrypoint `assistantMain` (app/lib/main.dart), which draws the sheet over the lower part of
 * the screen. Started by [WendelinVoiceSession] via `startAssistantActivity`.
 *
 * Shows over the lock screen; the Dart side then asks to unlock first and shows nothing personal
 * (see ADR 0006). Leaving the overlay (home, screen off) closes it.
 */
class AssistantActivity : WendelinActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        // Arrived before the Flutter engine starts (that may take a while on a cold start).
        VoiceLog.i("overlay-create restored=${savedInstanceState != null}")
        lastArrival = SystemClock.elapsedRealtime()
        AssistantArrivals.arrived()
        super.onCreate(savedInstanceState)
        // Personal content: no screenshots, not visible in the app switcher.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
        }
    }

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
        // The late twin of the first start (cold start): no second request.
        if (triggers) assistant?.trigger()
    }

    companion object {
        /** Intent extra: the session starts the overlay a second time (B10). */
        const val EXTRA_RETRY = "app.wendelin.assistant.retry"
    }

    // When the overlay last arrived (create or new intent), elapsed realtime.
    private var lastArrival: Long? = null

    override fun onDestroy() {
        VoiceLog.i("overlay-destroy finishing=$isFinishing")
        super.onDestroy()
    }

    override fun onStop() {
        super.onStop()
        // The overlay belongs to the moment it was opened; it does not stay in the background.
        // Dart closes first (stops microphone, speech output, request), then finishes.
        if (isChangingConfigurations || assistant?.unlocking == true || isFinishing) return
        val channel = assistant
        VoiceLog.i("overlay-stop engine=${channel != null}")
        if (channel == null) {
            finish()
        } else {
            channel.requestClose { how ->
                VoiceLog.i("overlay-close by=$how finishing=$isFinishing")
                if (!isFinishing) finish()
            }
        }
    }
}
