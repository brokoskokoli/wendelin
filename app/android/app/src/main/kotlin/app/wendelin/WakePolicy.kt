package app.wendelin

/** When the wake-word service should listen (setting „Bedingung“, WP50). */
enum class WakeMode(val key: String) {
    /** Only while the device charges (default). */
    CHARGING("charging"),

    /** Always, while the service is on. */
    ALWAYS("always"),
    ;

    companion object {
        /** Unknown values fall back to the default [CHARGING]. */
        fun parse(key: String?): WakeMode = entries.firstOrNull { it.key == key } ?: CHARGING
    }
}

/** The wake-word settings the app mirrors for the service (no database in the service). */
data class WakeSettings(
    val enabled: Boolean = false,
    val mode: WakeMode = WakeMode.CHARGING,
    /** Stage 2 (Whisper check) on or off, `wake.verify` of the app. */
    val verify: Boolean = true,
    /** „Pause 1 h“: nothing starts before this time (epoch ms), 0 = not paused. */
    val pausedUntilMs: Long = 0L,
) {
    /**
     * [old] changed by the channel arguments `enabled`, `mode`, `verify`; missing or invalid
     * values keep the old ones. Switching off also ends a pause.
     */
    fun withArgs(args: Map<*, *>?): WakeSettings {
        val on = args?.get("enabled") as? Boolean ?: enabled
        return WakeSettings(
            enabled = on,
            mode = (args?.get("mode") as? String)?.let { WakeMode.parse(it) } ?: mode,
            verify = args?.get("verify") as? Boolean ?: verify,
            pausedUntilMs = if (on) pausedUntilMs else 0L,
        )
    }
}

/** Whether the service may run now, or why not (the reason goes to the log as is). */
sealed interface WakeDecision {
    data object Start : WakeDecision

    data class Skip(val reason: String) : WakeDecision
}

/** Start/stop logic of the wake-word service without Android types (JVM test). */
object WakePolicy {
    /**
     * Order of the reasons: off, no assistant role (decision 5), no microphone permission,
     * paused, not charging (only in mode [WakeMode.CHARGING]).
     */
    fun decide(
        settings: WakeSettings,
        holdsRole: Boolean,
        micGranted: Boolean,
        charging: Boolean,
        nowMs: Long,
    ): WakeDecision = when {
        !settings.enabled -> WakeDecision.Skip("disabled")
        !holdsRole -> WakeDecision.Skip("no-role")
        !micGranted -> WakeDecision.Skip("no-permission")
        settings.pausedUntilMs > nowMs -> WakeDecision.Skip("paused")
        settings.mode == WakeMode.CHARGING && !charging -> WakeDecision.Skip("not-charging")
        else -> WakeDecision.Start
    }

    // Values of AudioManager.MODE_* (kept as numbers so no Android class is needed here).
    private const val MODE_IN_CALL = 2
    private const val MODE_IN_COMMUNICATION = 3
    private const val MODE_CALL_SCREENING = 4

    /**
     * Why the microphone must be free right now: `call` (phone or voice call) or `recording`
     * (another recording is active), else `null`.
     */
    fun conflict(audioMode: Int, foreignRecording: Boolean): String? = when {
        audioMode == MODE_IN_CALL ||
            audioMode == MODE_IN_COMMUNICATION ||
            audioMode == MODE_CALL_SCREENING -> "call"
        foreignRecording -> "recording"
        else -> null
    }

    /** Whether a service that runs for [mode] has to stop when charging changes to [charging]. */
    fun stopsOnUnplug(mode: WakeMode, charging: Boolean): Boolean =
        mode == WakeMode.CHARGING && !charging
}

/**
 * The audio of a wake word hit between the service and the overlay (both live in this process):
 * the service puts it down before `showSession`, the overlay's Dart side takes it once. A hit
 * nobody took within [MAX_AGE_MS] is stale.
 */
object WakeHandoff {
    const val MAX_AGE_MS = 30_000L

    private var pcm: ByteArray? = null
    private var at = 0L

    @Synchronized
    fun put(pcm: ByteArray, nowMs: Long) {
        this.pcm = pcm
        at = nowMs
    }

    /** The waiting pre-roll (16 kHz PCM16), once; `null` if none or stale. */
    @Synchronized
    fun take(nowMs: Long): ByteArray? {
        val p = pcm
        pcm = null
        return if (p != null && nowMs - at <= MAX_AGE_MS) p else null
    }

    /** Whether a hit waits for the overlay. */
    @Synchronized
    fun pending(): Boolean = pcm != null

    @Synchronized
    fun clear() {
        pcm = null
    }
}
