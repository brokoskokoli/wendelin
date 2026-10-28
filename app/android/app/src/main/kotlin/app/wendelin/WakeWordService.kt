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
    private val inbox = java.util.concurrent.ConcurrentLinkedQueue<Pair<ByteArray, Long>>()
    private val tap = WakeMicTap()
    private var watcher: WakeConflictWatcher? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var resume: Runnable? = null
    private val handoffCheck = TimedGuard(main)
    private val hitFlow = WakeHitFlow(this, main, handoffCheck, ::stopMic) { engine?.send("overlayClosed", null) }
    private val overlapGuard = TimedGuard(main)

    private val gap = WakeGapState(this) { engine != null }
    /** WP149: while [overlapGuard] is armed the hit is taken with the capture kept open. */
    private val conflicts = WakeConflictReaction(overlapGuard, ::stopMic)
    private val micDeferral = WakeMicDeferral(main, hasMic = { mic != null }, startMic = ::startMic)

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START
        val source = intent?.getStringExtra(EXTRA_SOURCE) ?: "?"
        // Whoever starts this service promises a notification within seconds.
        if (!goForeground(gap.notification())) {
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
                WakeSettingsStore.save(this, WakeSettingsStore.load(this).copy(enabled = false, pausedUntilMs = 0L, offByUser = true))
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
            engine?.send("run", settings.runArgs(StationState.active))
            VoiceLog.i("wake-start result=ok source=$source again=true")
            return
        }
        val e = RecognizerEngine(this, ::onEngineCall, "wakeWordMain", ENGINE_CHANNEL)
        engine = e
        e.send("run", settings.runArgs(StationState.active))
        watcher = WakeConflictWatcher(this, main, { mic?.sessionId ?: 0 }) { reason ->
            // Do not depend on Dart alone: a call or foreign recording closes the microphone here
            // (WP149: not the app's own AudioRecord in the hand-over overlap).
            conflicts.react(reason)
            engine?.send("conflict", mapOf("reason" to reason))
        }.also { it.start() }
        wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "wendelin:wake").also { it.acquire() }
        WakeNotifications.update(this, gap.notification())
        VoiceLog.i("wake-start result=ok source=$source mode=${settings.mode.key}")
    }

    /** Calls from the Dart side of the engine (main thread). */
    private fun onEngineCall(call: MethodCall) {
        when (call.method) {
            // While the hit's audio is collected, the microphone stays as it is (WP68).
            "startMic" -> if (!WakePolicy.ignoresMicCalls(WakeHandoff.capturing(), mic != null)) micDeferral.request()
            "stopMic" -> if (!WakePolicy.ignoresMicCalls(WakeHandoff.capturing(), mic != null)) {
                micDeferral.clear()
                stopMic()
            }
            "hit" -> onHit(call)
            "stage2Gap" -> gap.onReport(call.argument<String>("reason"))
            "failed" -> {
                val reported = call.argument<String>("reason")
                VoiceLog.i("wake-failed reason=${reported ?: "?"}")
                // modelMissing is no „Wieder einschalten“ case: the model stays missing.
                end(WakePolicy.failureReason(reported))
            }
        }
    }

    private fun startMic() {
        if (mic != null) return
        if (!WakePolicy.mayStartMic(conflicts.last)) {
            VoiceLog.i("wake-mic-start skipped=conflict reason=${conflicts.last}")
            return
        }
        val source = MicAudioSource(this)
        tap.reset()
        try {
            source.start(
                onChunk = { pcm ->
                    // Stamped on the reading thread; handled in order on the main thread.
                    inbox.add(pcm to System.currentTimeMillis())
                    main.post { drainInbox() }
                },
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

    /** Chunks go to Dart, or, after a hit, to the audio kept for the overlay (WP68). */
    private fun drainInbox() {
        while (true) {
            val (pcm, atMs) = inbox.poll() ?: break
            // Closed meanwhile: late chunks are dropped, they must not reach the paused Dart engine.
            if (mic == null && !WakeHandoff.capturing()) continue
            onMicChunk(pcm, atMs)
        }
    }

    private fun onMicChunk(pcm: ByteArray, atMs: Long) {
        if (WakeHandoff.capturing()) {
            WakeHandoff.append(pcm, atMs)
            return
        }
        tap.onChunk(pcm)
        engine?.send("audio", mapOf("pcm" to pcm))
    }

    private fun stopMic() {
        mic?.stop()
        mic = null
        inbox.clear()
    }

    /**
     * The overlay is about to take the hit's audio (main thread): the microphone is closed for
     * good, the reading thread has ended (no second `AudioRecord` next to the overlay's, WP51) and
     * every chunk it delivered is in the collected audio before [WakeHandoff.take].
     */
    private fun closeMicForHandoff() {
        val m = mic ?: return
        m.stopAndWait(MIC_JOIN_MS)
        drainInbox()
        stopMic()
    }

    /**
     * A confirmed wake word. The microphone stays open (WP68): what is said while the overlay
     * starts is kept next to the pre-roll, and [onHandoffTaken] closes the microphone when the
     * overlay takes the audio and opens its own right after.
     */
    private fun onHit(call: MethodCall) {
        VoiceLog.i("wake-hit kw=${call.argument<String>("kw") ?: "wake"} score=${call.argument<String>("score") ?: "?"}")
        WakeHandoff.put(
            call.argument<ByteArray>("pcm") ?: ByteArray(0),
            System.currentTimeMillis(),
            call.argument<Number>("end")?.toInt() ?: 0,
        )
        val pos = call.argument<Number>("pos")?.toLong()
        if (mic != null) WakeHandoff.beginCapture(if (pos != null) tap.tailAfter(pos) else ByteArray(0))
        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as android.app.KeyguardManager
        val route = WakePolicy.routeHit(
            ChatState.visible,
            keyguard.isKeyguardLocked,
            WakeChannel.available,
            StationState.active,
        )
        VoiceLog.i("wake-hit route=${route.name.lowercase()}")
        if (route == HitRoute.CHAT) hitFlow.askChat() else hitFlow.openOverlay()
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
                WakeTexts.load(this).ended(reason),
                withAction = reason != "no-role",
            )
        }
    }

    /** Frees microphone, engine, wake lock and conflict watch (not the notification). */
    private fun release() {
        resume?.let { main.removeCallbacks(it) }
        resume = null
        handoffCheck.disarm()
        overlapGuard.disarm()
        micDeferral.clear()
        watcher?.stop()
        watcher = null
        conflicts.reset()
        gap.reset()
        stopMic()
        // A hit that was being handed over dies with the service (else `capturing` stays set).
        WakeHandoff.clear()
        engine?.destroy()
        engine = null
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
    }

    /**
     * WP146: the app took the hit's audio but the service keeps recording until the app's own
     * microphone has delivered its first frame ([finishHandoff]); a guard ends it if that never
     * happens.
     */
    private fun handoffKept() {
        handoffCheck.disarm()
        overlapGuard.arm(OVERLAP_GUARD_MS) {
            VoiceLog.i("wake-handoff overlap=timeout")
            closeMicForHandoff()
            // What was collected stays for `finishHandoff`.
            WakeHandoff.stopCapture()
            stopMic()
        }
    }

    /**
     * WP146: the app's microphone delivers: the service stops now (no second `AudioRecord`
     * from here on) and returns what it recorded since the take.
     */
    private fun finishHandoff(): WakeHandoff.Taken? {
        overlapGuard.disarm()
        closeMicForHandoff()
        val tail = WakeHandoff.finish()
        stopMic()
        return tail
    }

    /** The overlay took the hit's audio: it opens the microphone now. */
    private fun handoffTaken() {
        handoffCheck.disarm()
        stopMic()
    }

    /** The overlay is gone (or never came): Dart may listen again. */
    private fun overlayClosed() {
        overlapGuard.disarm()
        if (WakeHandoff.pending() || WakeHandoff.capturing()) {
            // Never taken (or never finished): the kept microphone closes, Dart opens it again.
            WakeHandoff.clear()
            stopMic()
        }
        // What the guard stopped collected stays for `finishHandoff`; nobody comes for it now
        // (up to 15 s of audio must not linger).
        WakeHandoff.clear()
        handoffCheck.disarm()
        engine?.send("overlayClosed", null)
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        release()
        super.onDestroy()
    }

    companion object {
        const val MIC_JOIN_MS = 300L
        const val ENGINE_CHANNEL = "app.wendelin/wake-engine"
        const val ACTION_START = "app.wendelin.wake.START"
        const val ACTION_STOP = "app.wendelin.wake.STOP"
        const val ACTION_PAUSE = "app.wendelin.wake.PAUSE"
        const val ACTION_RESUME = "app.wendelin.wake.RESUME"
        const val ACTION_OFF = "app.wendelin.wake.OFF"
        const val EXTRA_SOURCE = "source"
        const val EXTRA_REASON = "reason"
        private const val HOUR_MS = 60 * 60 * 1000L
        const val HANDOFF_TIMEOUT_MS = 15_000L

        /** Longest time the service records next to the app's microphone opening (WP146). */
        const val OVERLAP_GUARD_MS = 2_500L
        const val SCREEN_ON_MS = 10_000L

        // Stops the user did not ask for: they leave the „Wieder einschalten“ hint.
        private val UNWANTED = setOf("engine-failed", "no-role")

        @Volatile private var instance: WakeWordService? = null

        /** Whether the service is alive in this process. */
        val running: Boolean get() = instance != null

        /**
         * The overlay took the hit's audio (main thread): the service closes its microphone at
         * once, so the overlay can open its own with the shortest possible hole in between.
         */
        fun beforeHandoffTake() {
            instance?.closeMicForHandoff()
        }

        fun onHandoffTaken() {
            instance?.handoffTaken()
        }

        /** WP146: taken with the capture kept open (the service records until [finishHandoff]). */
        fun onHandoffKept() {
            instance?.handoffKept()
        }

        /** WP146: the app's microphone is up; stops the service and returns the audio since the take. */
        fun finishHandoff(): WakeHandoff.Taken? = instance?.finishHandoff() ?: WakeHandoff.finish()

        /**
         * Debug builds only (WP93, device tests): a hit with a second of silence as pre-roll, as
         * if the engine had confirmed the wake word. `false` if the service is not running.
         */
        fun debugHit(context: Context): Boolean {
            val s = instance ?: return false
            if (!WakePolicy.allowsDebugHit(context.applicationInfo.flags)) return false
            s.main.post {
                s.onHit(MethodCall("hit", mapOf("kw" to "debug", "pcm" to ByteArray(32_000), "end" to 16_000)))
            }
            return true
        }

        /** WP146: an engine of the app reports that it records (or not); see [AppVoice]. */
        fun onAppVoice(source: String, active: Boolean) {
            AppVoice.set(source, active, System.currentTimeMillis())
            val s = instance ?: return
            s.main.post { s.micDeferral.appVoiceChanged() }
        }

        /** WP148: the developer mode changed; the running wake engine follows without a restart. */
        fun onDevMode(on: Boolean, clear: Boolean = false, archive: Boolean = false) {
            instance?.let { s -> s.main.post { s.engine?.send("devMode", WakePolicy.devModeArgs(on, clear, archive)) } }
        }

        /** WP171: the app changed what stage 2 needs (model, voice); the engine checks the gap again. */
        fun onRecheck() { instance?.let { s -> s.main.post { s.engine?.send("recheck", null) } } }

        /** The assistant overlay was closed: the service listens again. */
        fun onOverlayClosed() {
            val s = instance ?: return
            s.main.post { s.overlayClosed() }
        }
    }
}

/** Channel arguments of `run` for the wake engine: stage 2, detector choice, station flag (WP129), developer mode (WP148). */
internal fun WakeSettings.runArgs(stationActive: Boolean): Map<String, Any> =
    mapOf("verify" to verify, "detector" to detector, "station" to stationActive, "dev" to devMode)
