package app.wendelin

import android.content.Context
import android.media.AudioManager
import android.media.AudioRecordingConfiguration
import android.os.Build
import android.os.Handler

/**
 * Watches for things that need the microphone more than the wake word: a phone or voice call
 * (`AudioManager.mode`) and a recording of another app (`getActiveRecordingConfigurations`,
 * not the own session [ownSession]). [onChange] gets the reason (`call`, `recording`) or `null`
 * once the microphone is free again; it runs on the main thread. See [WakePolicy.conflict].
 */
class WakeConflictWatcher(
    context: Context,
    private val main: Handler,
    private val ownSession: () -> Int,
    private val onChange: (String?) -> Unit,
) {
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var last: String? = null
    private var running = false

    private val callback = object : AudioManager.AudioRecordingCallback() {
        override fun onRecordingConfigChanged(configs: MutableList<AudioRecordingConfiguration>) {
            refresh(configs)
        }
    }

    // The mode of a call has no callback before Android 12, so it is polled as well.
    private val poll = object : Runnable {
        override fun run() {
            if (!running) return
            refresh(audio.activeRecordingConfigurations)
            main.postDelayed(this, POLL_MS)
        }
    }

    fun start() {
        if (running) return
        running = true
        last = null
        audio.registerAudioRecordingCallback(callback, main)
        main.post(poll)
    }

    fun stop() {
        if (!running) return
        running = false
        audio.unregisterAudioRecordingCallback(callback)
        main.removeCallbacks(poll)
    }

    private fun refresh(configs: List<AudioRecordingConfiguration>) {
        val own = ownSession()
        val foreign = configs.any {
            it.clientAudioSessionId != own &&
                !(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && it.isClientSilenced)
        }
        val reason = reasonFor(audio.mode, foreign)
        if (reason != last) {
            last = reason
            onChange(reason)
        }
    }

    companion object {
        private const val POLL_MS = 2000L

        /** The reason for the current state; the app's own call path ([SpeechRoute.active]) is no call. */
        internal fun reasonFor(audioMode: Int, foreignRecording: Boolean): String? =
            WakePolicy.conflictNow(audioMode, foreignRecording)
    }
}
