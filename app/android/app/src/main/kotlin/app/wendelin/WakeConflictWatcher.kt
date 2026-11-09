package app.wendelin

import android.content.Context
import android.media.AudioManager
import android.media.AudioRecordingConfiguration
import android.os.Build
import android.os.Handler

/** One active recording as the watcher sees it (session id, silenced by the system). */
internal data class RecordingClient(val session: Int, val silenced: Boolean)

/**
 * Watches for things that need the microphone more than the wake word: a phone or voice call
 * (`AudioManager.mode`) and a recording of another app (`getActiveRecordingConfigurations`,
 * not the own sessions [ownSessions]). [onChange] gets the reason (`call`, `recording`) or `null`
 * once the microphone is free again; it runs on the main thread. See [WakePolicy.conflict].
 */
class WakeConflictWatcher(
    context: Context,
    private val main: Handler,
    private val ownSessions: () -> Set<Int>,
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
        val silencedKnown = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        val clients = configs.map {
            RecordingClient(it.clientAudioSessionId, silencedKnown && it.isClientSilenced)
        }
        val reason = reasonFor(audio.mode, ownSessions(), clients, OwnCommMode.active)
        if (reason != last) {
            last = reason
            onChange(reason)
        }
    }

    companion object {
        private const val POLL_MS = 2000L

        /**
         * The reason for the current state: a recording of another session that is not silenced
         * counts.
         */
        internal fun reasonFor(audioMode: Int, ownSession: Int, clients: List<RecordingClient>): String? =
            reasonFor(audioMode, setOf(ownSession), clients)

        /** WP188: while the microphone moves to another device two own recordings run at once. */
        internal fun reasonFor(
            audioMode: Int,
            ownSessions: Set<Int>,
            clients: List<RecordingClient>,
            ownCommMode: Boolean = false,
        ): String? {
            val foreign = clients.any { it.session !in ownSessions && !it.silenced }
            return WakePolicy.conflict(audioMode, foreign, ownCommMode)
        }
    }
}
