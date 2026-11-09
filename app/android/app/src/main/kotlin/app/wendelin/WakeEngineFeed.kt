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

    /** [pcm] goes to the engine now: counted, returned as the arguments of the `audio` call. */
    fun send(pcm: ByteArray): Map<String, Any> {
        tap.onChunk(pcm)
        return mapOf("pcm" to pcm, "token" to token)
    }
}
