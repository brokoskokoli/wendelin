package app.wendelin

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import io.flutter.plugin.common.MethodCall

/**
 * The wake-word service (WP50, ADR 0013): a foreground service of type `microphone`, not
 * exported. It owns the microphone ([MicAudioSource], `VOICE_RECOGNITION`) and a headless Flutter
 * engine running `wakeWordMain` (app/lib/platform/wake/wake_host.dart): detection, stage 2 and
 * the decision happen in Dart; this class records on request, watches for conflicts, shows the
 * notification and, on a hit, hands the audio to the assistant overlay.
 *
 * Diagnostics under the tag `Wendelin/voice` (never audio or text): `wake-start`, `wake-hit`,
 * `wake-pause`, `wake-conflict`, `wake-stop`, plus the lines Dart sends (`wake-cand`,
 * `wake-verify`, `wake-alive`).
 */
class WakeWordService : Service() {
    private val main = Handler(Looper.getMainLooper())
    private var engine: RecognizerEngine? = null
    private var mic: MicAudioSource? = null
    private var watcher: WakeConflictWatcher? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var resume: Runnable? = null
    private var handoffCheck: Runnable? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START
        val source = intent?.getStringExtra(EXTRA_SOURCE) ?: "?"
        // Whoever starts this service promises a notification within seconds.
        if (!goForeground(WakeNotifications.listening(this))) {
            VoiceLog.i("wake-start result=fgs-denied source=$source")
            stopSelf()
            return START_NOT_STICKY
        }
        when (action) {
            ACTION_START -> begin(source)
            ACTION_STOP -> end(intent?.getStringExtra(EXTRA_REASON) ?: "stop")
            ACTION_PAUSE -> pauseForAnHour()
            ACTION_RESUME -> {
                WakeSettingsStore.save(this, WakeSettingsStore.load(this).copy(pausedUntilMs = 0L))
                begin("resume")
            }
            ACTION_OFF -> {
                WakeSettingsStore.save(this, WakeSettingsStore.load(this).copy(enabled = false, pausedUntilMs = 0L))
                end("user-off")
            }
        }
        return START_NOT_STICKY
    }

    private fun goForeground(notification: android.app.Notification): Boolean = try {
        if (WakeStarter.hasServiceType) {
            startForeground(WakeNotifications.ID_SERVICE, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(WakeNotifications.ID_SERVICE, notification)
        }
        true
    } catch (e: Exception) {
        VoiceLog.i("wake-start error=${e.javaClass.simpleName}")
        false
    }

    private fun begin(source: String) {
        resume?.let { main.removeCallbacks(it) }
        val settings = WakeSettingsStore.load(this)
        val decision = WakePolicy.decide(
            settings,
            holdsRole = RecognizerSwitch.holdsAssistantRole(this),
            micGranted = WakeStarter.micGranted(this),
            charging = WakeStarter.isCharging(this),
            nowMs = System.currentTimeMillis(),
        )
        if (decision is WakeDecision.Skip) {
            if (decision.reason == "paused") {
                enterPause(settings.pausedUntilMs)
            } else {
                VoiceLog.i("wake-start result=${decision.reason} source=$source")
                end(decision.reason)
            }
            return
        }
        if (engine != null) {
            // Already listening: only the settings may have changed.
            engine?.send("run", mapOf("verify" to settings.verify))
            VoiceLog.i("wake-start result=ok source=$source again=true")
            return
        }
        val e = RecognizerEngine(this, ::onEngineCall, "wakeWordMain", ENGINE_CHANNEL)
        engine = e
        e.send("run", mapOf("verify" to settings.verify))
        watcher = WakeConflictWatcher(this, main, { mic?.sessionId ?: 0 }) { reason ->
            VoiceLog.i("wake-conflict reason=${reason ?: "none"}")
            // Do not depend on Dart alone: a call or foreign recording closes the microphone here.
            if (WakePolicy.closesMicFor(reason)) stopMic()
            engine?.send("conflict", mapOf("reason" to reason))
        }.also { it.start() }
        wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "wendelin:wake").also { it.acquire() }
        WakeNotifications.update(this, WakeNotifications.listening(this))
        VoiceLog.i("wake-start result=ok source=$source mode=${settings.mode.key}")
    }

    /** Calls from the Dart side of the engine (main thread). */
    private fun onEngineCall(call: MethodCall) {
        when (call.method) {
            "startMic" -> startMic()
            "stopMic" -> stopMic()
            "hit" -> onHit(call)
            "failed" -> {
                VoiceLog.i("wake-failed reason=${call.argument<String>("reason") ?: "?"}")
                end("engine-failed")
            }
        }
    }

    private fun startMic() {
        if (mic != null) return
        val source = MicAudioSource(this)
        try {
            source.start(
                onChunk = { pcm -> main.post { engine?.send("audio", mapOf("pcm" to pcm)) } },
                onError = { error ->
                    main.post {
                        stopMic()
                        VoiceLog.i("wake-mic-error error=${error.javaClass.simpleName}")
                        engine?.send("audioError", mapOf("message" to error.javaClass.simpleName))
                    }
                },
            )
            mic = source
        } catch (e: Exception) {
            VoiceLog.i("wake-mic-error error=${e.javaClass.simpleName}")
            engine?.send("audioError", mapOf("message" to e.javaClass.simpleName))
        }
    }

    private fun stopMic() {
        mic?.stop()
        mic = null
    }

    /** A confirmed wake word: the microphone is free (Dart stopped it), the overlay takes over. */
    private fun onHit(call: MethodCall) {
        stopMic()
        VoiceLog.i("wake-hit kw=${call.argument<String>("kw") ?: "wake"} score=${call.argument<String>("score") ?: "?"}")
        WakeHandoff.put(call.argument<ByteArray>("pcm") ?: ByteArray(0), System.currentTimeMillis())
        wakeScreen()
        if (!WendelinVoiceInteractionService.show()) {
            VoiceLog.i("wake-hit show=failed")
            WakeHandoff.clear()
            engine?.send("overlayClosed", null)
            return
        }
        // The overlay takes the audio when it starts; if it never does, listen again.
        val check = Runnable {
            if (WakeHandoff.pending()) {
                VoiceLog.i("wake-hit overlay=missing")
                WakeHandoff.clear()
                engine?.send("overlayClosed", null)
            }
        }
        handoffCheck = check
        main.postDelayed(check, HANDOFF_TIMEOUT_MS)
    }

    /**
     * Turns the screen on for the overlay (a hit with the screen off): the overlay has no frame
     * to draw otherwise. The device stays locked; the lock screen path of WP53 applies.
     */
    @Suppress("DEPRECATION")
    private fun wakeScreen() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        pm.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "wendelin:wake-screen",
        ).acquire(SCREEN_ON_MS)
    }

    private fun pauseForAnHour() {
        val until = System.currentTimeMillis() + HOUR_MS
        WakeSettingsStore.save(this, WakeSettingsStore.load(this).copy(pausedUntilMs = until))
        VoiceLog.i("wake-pause reason=user until=$until")
        enterPause(until)
    }

    private fun enterPause(untilMs: Long) {
        release()
        WakeNotifications.update(this, WakeNotifications.paused(this, untilMs))
        val r = Runnable { onStartCommand(Intent(ACTION_RESUME), 0, 0) }
        resume = r
        main.postDelayed(r, maxOf(1000L, untilMs - System.currentTimeMillis()))
    }

    /** Ends the service. [reason] is logged; a reason the user did not ask for shows a hint. */
    private fun end(reason: String) {
        release()
        VoiceLog.i("wake-stop reason=$reason")
        WakeSettingsStore.setLastStop(this, reason)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        if (reason in UNWANTED) {
            WakeNotifications.showReenable(
                this,
                "Das Wake Word wurde beendet ($reason). Tippe, um es wieder einzuschalten.",
                withAction = reason != "no-role",
            )
        }
    }

    /** Frees microphone, engine, wake lock and conflict watch (not the notification). */
    private fun release() {
        resume?.let { main.removeCallbacks(it) }
        resume = null
        handoffCheck?.let { main.removeCallbacks(it) }
        handoffCheck = null
        watcher?.stop()
        watcher = null
        stopMic()
        engine?.destroy()
        engine = null
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
    }

    /** The overlay is gone (or never came): Dart may listen again. */
    private fun overlayClosed() {
        handoffCheck?.let { main.removeCallbacks(it) }
        handoffCheck = null
        engine?.send("overlayClosed", null)
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        release()
        super.onDestroy()
    }

    companion object {
        const val ENGINE_CHANNEL = "app.wendelin/wake-engine"
        const val ACTION_START = "app.wendelin.wake.START"
        const val ACTION_STOP = "app.wendelin.wake.STOP"
        const val ACTION_PAUSE = "app.wendelin.wake.PAUSE"
        const val ACTION_RESUME = "app.wendelin.wake.RESUME"
        const val ACTION_OFF = "app.wendelin.wake.OFF"
        const val EXTRA_SOURCE = "source"
        const val EXTRA_REASON = "reason"
        private const val HOUR_MS = 60 * 60 * 1000L
        private const val HANDOFF_TIMEOUT_MS = 15_000L
        private const val SCREEN_ON_MS = 10_000L

        // Stops the user did not ask for: they leave the „Wieder einschalten“ hint.
        private val UNWANTED = setOf("engine-failed", "no-role")

        @Volatile private var instance: WakeWordService? = null

        /** Whether the service is alive in this process. */
        val running: Boolean get() = instance != null

        /** The assistant overlay was closed: the service listens again. */
        fun onOverlayClosed() {
            val s = instance ?: return
            s.main.post { s.overlayClosed() }
        }
    }
}
