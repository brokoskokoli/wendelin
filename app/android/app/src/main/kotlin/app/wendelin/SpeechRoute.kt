package app.wendelin

/** What the speech route needs from Android (so the logic runs on the JVM). */
interface RouteAudio {
    /** `Build.VERSION.SDK_INT`. */
    val sdk: Int

    /** `AudioManager.mode`. */
    var mode: Int

    /** `AudioManager.isSpeakerphoneOn`. */
    var speakerphoneOn: Boolean

    /** The communication device (API 31+, opaque here); `null` clears the choice. */
    var communicationDevice: Any?

    /** The built-in speaker as a device (API 31+), `null` if there is none. */
    fun builtinSpeaker(): Any?

    /** A headset, wired or Bluetooth output is the active output. */
    fun externalOutputActive(): Boolean
}

/**
 * WP118 (K88): the spoken answer in the call path (`MODE_IN_COMMUNICATION`, output on the speaker
 * unless a headset or Bluetooth is active), so the echo canceller of the call path works. [enter]
 * remembers the state before, [leave] restores it; both are idempotent. [active] tells the
 * wake-word watcher that this mode is the app's own (see [WakePolicy.conflict]).
 */
class SpeechRoute(private val audio: RouteAudio, private val log: (String) -> Unit = {}) {
    /** Switches to the call path; returns the output (`speaker`, `external`). Asking twice is fine. */
    fun enter(): String = synchronized(lock) {
        if (saved != null) return device(audio.externalOutputActive())
        val before = Saved(audio.mode, audio.speakerphoneOn, communicationDeviceOrNull())
        saved = before
        active = true
        val external = audio.externalOutputActive()
        try {
            audio.mode = MODE_IN_COMMUNICATION
            if (!external) toSpeaker()
        } catch (e: RuntimeException) {
            leave()
            throw e
        }
        val device = device(external)
        log("speech-route mode=communication device=$device")
        device
    }

    /**
     * Restores what [enter] found. The mode is restored even if the device cannot be. [active]
     * turns false only after that, so the watcher never sees the mode without the flag.
     */
    fun leave(): Unit = synchronized(lock) {
        val before = saved ?: return
        saved = null
        try {
            if (audio.sdk >= 31) audio.communicationDevice = before.device
            else audio.speakerphoneOn = before.speaker
        } finally {
            try {
                audio.mode = before.mode
            } finally {
                active = false
            }
            log("speech-route mode=normal device=restored")
        }
    }

    private fun toSpeaker() {
        if (audio.sdk >= 31) {
            val speaker = audio.builtinSpeaker()
            if (speaker != null) {
                audio.communicationDevice = speaker
                return
            }
        }
        audio.speakerphoneOn = true
    }

    private fun communicationDeviceOrNull(): Any? = if (audio.sdk >= 31) audio.communicationDevice else null

    private fun device(external: Boolean) = if (external) "external" else "speaker"

    private class Saved(val mode: Int, val speaker: Boolean, val device: Any?)

    companion object {
        const val MODE_IN_COMMUNICATION = 3

        // One state per process: MainActivity and AssistantActivity each own a route, but there is
        // only one audio mode. The first enter saves the state, any leave gives it back.
        private val lock = Any()
        private var saved: Saved? = null

        /** Whether the app itself holds the call path right now (any thread). */
        @Volatile
        var active = false
            private set
    }
}
