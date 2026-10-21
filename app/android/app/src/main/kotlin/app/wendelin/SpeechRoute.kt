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
    private var saved: Saved? = null

    private class Saved(val mode: Int, val speaker: Boolean, val device: Any?)

    /** Switches to the call path; returns the output (`speaker`, `external`). Asking twice is fine. */
    @Synchronized
    fun enter(): String {
        saved?.let { return device(audio.externalOutputActive()) }
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
        log("speech-route mode=communication usage=voice_communication device=$device")
        return device
    }

    /** Restores what [enter] found. The mode is restored even if the device cannot be. */
    @Synchronized
    fun leave() {
        val before = saved ?: return
        saved = null
        active = false
        try {
            if (audio.sdk >= 31) audio.communicationDevice = before.device
            else audio.speakerphoneOn = before.speaker
        } finally {
            audio.mode = before.mode
            log("speech-route mode=normal usage=assistant device=restored")
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

    companion object {
        const val MODE_IN_COMMUNICATION = 3

        /** Whether the app itself holds the call path right now (any thread). */
        @Volatile
        var active = false
            private set
    }
}
