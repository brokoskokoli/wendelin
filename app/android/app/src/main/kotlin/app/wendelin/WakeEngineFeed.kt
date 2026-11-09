package app.wendelin

/**
 * The audio the wake engine's Dart listener gets from the central recording (WP189), counted in
 * the same frame as the listener's stream position, so [WakeMicTap.tailAfter] hands over only the
 * frames that were still on their way at a hit.
 *
 * Since the central recording (WP180) the microphone keeps running while the listener pauses
 * (overlay) and the hub holds the wake stream back during a dialog. Counting every microphone
 * chunk from the opening of the microphone therefore ran ahead of the listener, whose position
 * starts at 0 on every resume: at a hit the tap returned its whole buffer (3 s, the wake word
 * again) and the request ended at once inside that doubled pre-roll.
 *
 * Here only the chunks sent to the engine count, and each new stream of the listener (its
 * `startMic` with a [token]) starts the count at 0. Every chunk carries the token it was counted
 * under; the Dart side drops chunks of an older token (still on their way when it restarted), so
 * both sides count exactly the same chunks. Main thread only.
 */
internal class WakeEngineFeed(val tap: WakeMicTap = WakeMicTap()) {
    /** Token of the listener's current stream (0 = none asked for yet). */
    var token = 0L
        private set

    /** The listener starts a new stream ([token] from its `startMic`): its position is 0 again. */
    fun restart(token: Long) {
        this.token = token
        tap.reset()
    }

    /**
     * Wires the engine into [hub]: each chunk is counted when the hub dispatches it (in order, on
     * the main thread), [deliver] gets the `audio` arguments (it may post them on).
     */
    fun attach(hub: CentralAudioHub, deliver: (Map<String, Any>) -> Unit) {
        hub.subscribe(AudioSubscriberKind.WAKE, ENGINE_ID, onChunk = { pcm -> deliver(send(pcm)) })
    }

    /**
     * The engine's `startMic` ([token], `null` = 0): the new stream counts from 0 in any case,
     * the microphone is only asked for ([request]) when the call is not [ignored] (WP68).
     */
    fun onStartMic(token: Long?, ignored: Boolean, request: () -> Unit) {
        restart(token ?: 0L)
        if (!ignored) request()
    }

    /** [pcm] goes to the engine now: counted, returned as the arguments of the `audio` call. */
    fun send(pcm: ByteArray): Map<String, Any> {
        tap.onChunk(pcm)
        return mapOf("pcm" to pcm, "token" to token)
    }

    companion object {
        const val ENGINE_ID = "wake-engine"
    }
}
