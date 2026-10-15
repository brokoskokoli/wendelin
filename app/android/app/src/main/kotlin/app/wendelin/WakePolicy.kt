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
    /**
     * Switched off by the notification's „Aus“ (not by the app). Set only there; every
     * `configure` of the app clears it. The app adopts an „Aus“ only with this flag, so a status
     * read before its own `configure(enabled=true)` cannot switch it off again.
     */
    val offByUser: Boolean = false,
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
            offByUser = if (args?.containsKey("enabled") == true) false else offByUser,
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

    /** Whether the microphone is closed by the service itself, not only by Dart: any conflict. */
    fun closesMicFor(conflict: String?): Boolean = conflict == "call" || conflict == "recording"

    /** Whether `startMic` of Dart may open the microphone while the last [conflict] holds. */
    fun mayStartMic(conflict: String?): Boolean = !closesMicFor(conflict)

    /** Whether a service that runs for [mode] has to stop when charging changes to [charging]. */
    fun stopsOnUnplug(mode: WakeMode, charging: Boolean): Boolean =
        mode == WakeMode.CHARGING && !charging
}

/**
 * The audio of a wake word hit between the service and the overlay (both live in this process):
 * the service puts it down before `showSession`, the overlay's Dart side takes it once. A hit
 * nobody took within [MAX_AGE_MS] is stale.
 *
 * WP68: the microphone of the service stays open after the hit and [append] collects what is said
 * while the overlay starts ([beginCapture] .. [take]); [take] returns the pre-roll and that audio
 * in one piece and ends the capture, so the overlay opens its microphone right after it with no
 * hole in between.
 */
object WakeHandoff {
    const val MAX_AGE_MS = 30_000L

    /** At most 15 s of audio (16 kHz, 16 bit) are collected; more is dropped. */
    const val MAX_CAPTURE_BYTES = 15 * 16_000 * 2

    /** What the overlay gets: PCM16 LE, the sample where the wake word ends, how much was collected. */
    class Taken(val pcm: ByteArray, val wakeEnd: Int, val capturedMs: Long)

    private var pcm: ByteArray? = null
    private var wakeEnd = 0
    private var at = 0L
    private var capturing = false
    private var tail = java.io.ByteArrayOutputStream()

    @Synchronized
    fun put(pcm: ByteArray, nowMs: Long, wakeEnd: Int = 0) {
        this.pcm = pcm
        this.wakeEnd = wakeEnd
        at = nowMs
        capturing = false
        tail = java.io.ByteArrayOutputStream()
    }

    /** From now on [append] collects; [prefix] is audio the Dart side did not see yet. */
    @Synchronized
    fun beginCapture(prefix: ByteArray) {
        tail = java.io.ByteArrayOutputStream().also { it.write(prefix) }
        capturing = pcm != null
    }

    @Synchronized
    fun capturing(): Boolean = capturing

    /** One chunk from the microphone while capturing (whole samples only). */
    @Synchronized
    fun append(chunk: ByteArray) {
        if (!capturing) return
        val room = MAX_CAPTURE_BYTES - tail.size()
        val n = minOf(chunk.size, room) and 1.inv()
        if (n > 0) tail.write(chunk, 0, n)
    }

    /** The waiting pre-roll (16 kHz PCM16) with the collected audio, once; `null` if none or stale. */
    @Synchronized
    fun take(nowMs: Long): Taken? {
        val p = pcm
        pcm = null
        capturing = false
        val extra = tail.toByteArray()
        tail = java.io.ByteArrayOutputStream()
        return if (p != null && nowMs - at <= MAX_AGE_MS) {
            Taken(p + extra, wakeEnd, extra.size / 2 * 1000L / 16_000)
        } else {
            null
        }
    }

    /** Whether a hit waits for the overlay. */
    @Synchronized
    fun pending(): Boolean = pcm != null

    @Synchronized
    fun clear() {
        pcm = null
        capturing = false
        tail = java.io.ByteArrayOutputStream()
    }
}

/**
 * The most recent microphone chunks the service sent to Dart (WP68). Dart confirms a wake word at
 * a stream position; frames that were already on their way meanwhile are not in its pre-roll, so
 * [tailAfter] hands them to the capture.
 */
class WakeMicTap(private val keepBytes: Int = 3 * 16_000 * 2) {
    private val recent = ArrayDeque<ByteArray>()
    private var bytes = 0

    /** Samples sent since the microphone was opened. */
    var sent = 0L
        private set

    fun reset() {
        recent.clear()
        bytes = 0
        sent = 0
    }

    fun onChunk(chunk: ByteArray) {
        sent += chunk.size / 2
        recent.addLast(chunk)
        bytes += chunk.size
        while (bytes - recent.first().size >= keepBytes) bytes -= recent.removeFirst().size
    }

    /** The samples after stream position [pos] (as far as they are still held). */
    fun tailAfter(pos: Long): ByteArray {
        val missing = (sent - pos).coerceAtLeast(0L) * 2
        val all = java.io.ByteArrayOutputStream().also { out -> recent.forEach { out.write(it) } }.toByteArray()
        val n = minOf(missing, all.size.toLong()).toInt()
        return all.copyOfRange(all.size - n, all.size)
    }
}
