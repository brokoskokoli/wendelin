package app.wendelin

/**
 * The two audio focus requests of the app (no Android types, so they run on the JVM). The values
 * are `AudioManager.AUDIOFOCUS_*` constants.
 *
 * - `duck`: the whole spoken answer; other players only get quieter and stay at the same
 *   position (`AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`).
 * - `listen`: the recording of a command; players pause for the moment and resume afterwards
 *   (`AUDIOFOCUS_GAIN_TRANSIENT`).
 */
object AudioFocusKinds {
    const val GAIN = 1
    const val GAIN_TRANSIENT = 2
    const val GAIN_TRANSIENT_MAY_DUCK = 3

    const val LOSS = -1
    const val LOSS_TRANSIENT = -2
    const val LOSS_TRANSIENT_CAN_DUCK = -3

    /**
     * What a focus change (`AUDIOFOCUS_*` of the listener) means for the app: `lost` (another app
     * took the focus, also for a moment), `gained` (it is back), or `null` for being asked to
     * duck (the recording has nothing to lower) and unknown values.
     */
    fun stateFor(change: Int): String? =
        when (change) {
            LOSS, LOSS_TRANSIENT -> "lost"
            GAIN -> "gained"
            else -> null
        }

    /** A permanent loss is not followed by a gain; the request is dead and must be asked anew. */
    fun isPermanent(change: Int): Boolean = change == LOSS

    /** Focus gain for [kind]; `null` for an unknown name. */
    fun gainFor(kind: String): Int? =
        when (kind) {
            "duck" -> GAIN_TRANSIENT_MAY_DUCK
            "listen" -> GAIN_TRANSIENT
            else -> null
        }
}
