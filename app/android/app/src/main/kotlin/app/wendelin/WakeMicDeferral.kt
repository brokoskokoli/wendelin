package app.wendelin

import android.os.Handler

/**
 * WP146: the engine wants the microphone. While the app records (or just did), the request waits,
 * so the service never records next to the app's microphone ([AppVoice]).
 */
internal class WakeMicDeferral(
    private val main: Handler,
    private val hasMic: () -> Boolean,
    private val startMic: () -> Unit,
) {
    private var wanted = false
    private var due: Runnable? = null

    /** The engine asks for the microphone: starts it now or after the app's quiet time. */
    fun request() {
        if (hasMic()) return
        clear()
        val wait = AppVoice.waitMs(System.currentTimeMillis())
        if (wait == 0L) {
            startMic()
            return
        }
        wanted = true
        VoiceLog.i("wake-mic-deferred app=${wait == AppVoice.WAIT_FOR_APP} waitMs=${wait.coerceAtLeast(0L)}")
        // While the app records the end is reported; the fallback ends a hanging report.
        val delay = if (wait > 0L) wait else AppVoice.MAX_ACTIVE_MS
        val task = Runnable {
            due = null
            if (wanted && !hasMic()) request()
        }
        due = task
        main.postDelayed(task, delay)
    }

    /** The app's recording state changed (main thread): a waiting microphone may start now. */
    fun appVoiceChanged() {
        if (wanted && !hasMic()) request()
    }

    /** The wish is gone (engine stopped the microphone, service ends). */
    fun clear() {
        wanted = false
        due?.let { main.removeCallbacks(it) }
        due = null
    }
}

/** One delayed task at a time on the main thread (re-arming replaces it). */
internal class TimedGuard(private val main: Handler) {
    private var task: Runnable? = null

    fun arm(delayMs: Long, run: () -> Unit) {
        disarm()
        val t = Runnable {
            task = null
            run()
        }
        task = t
        main.postDelayed(t, delayMs)
    }

    fun disarm() {
        task?.let { main.removeCallbacks(it) }
        task = null
    }
}

/**
 * The route of a confirmed hit (WP93): the chat decides, otherwise the overlay opens; if nobody
 * takes the audio in time, the service listens again ([handoffCheck]).
 */
internal class WakeHitFlow(
    private val context: android.content.Context,
    private val main: Handler,
    private val handoffCheck: TimedGuard,
    private val stopMic: () -> Unit,
    private val overlayClosed: () -> Unit,
) {
    /** WP93: the main engine decides (it checks again); no answer in time means the overlay. */
    fun askChat() {
        ChatHitArbiter(
            scheduler = object : HitScheduler {
                override fun postDelayed(delayMs: Long, task: Runnable) {
                    main.postDelayed(task, delayMs)
                }

                override fun cancel(task: Runnable) = main.removeCallbacks(task)
            },
            openOverlay = {
                VoiceLog.i("wake-hit chat=refused-or-timeout")
                openOverlay()
            },
            chatAccepted = {
                VoiceLog.i("wake-hit chat=accepted")
                armHandoffCheck()
            },
        ).begin { done -> WakeChannel.askHit(done) }
    }

    fun openOverlay() {
        wakeScreen()
        if (!WendelinVoiceInteractionService.show()) {
            VoiceLog.i("wake-hit show=failed")
            WakeHandoff.clear()
            stopMic()
            overlayClosed()
            return
        }
        armHandoffCheck()
    }

    /** The overlay (or chat) takes the audio when it starts; if it never does, listen again. */
    private fun armHandoffCheck() {
        handoffCheck.arm(WakeWordService.HANDOFF_TIMEOUT_MS) {
            if (WakeHandoff.pending()) {
                VoiceLog.i("wake-hit overlay=missing")
                WakeHandoff.clear()
                stopMic()
                ChatState.owned = false
                overlayClosed()
            }
        }
    }

    /**
     * Turns the screen on for the overlay (a hit with the screen off): the overlay has no frame
     * to draw otherwise. The device stays locked; the lock screen path of WP53 applies.
     */
    @Suppress("DEPRECATION")
    private fun wakeScreen() {
        val pm = context.getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager
        pm.newWakeLock(
            android.os.PowerManager.SCREEN_BRIGHT_WAKE_LOCK or android.os.PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "wendelin:wake-screen",
        ).acquire(WakeWordService.SCREEN_ON_MS)
    }
}
