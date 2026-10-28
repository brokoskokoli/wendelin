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
    /** Stage 1 detection choice (WP129): `auto`, `templates` or `model`. */
    val detector: String = "auto",
    /** „Pause 1 h“: nothing starts before this time (epoch ms), 0 = not paused. */
    val pausedUntilMs: Long = 0L,
    /**
     * Switched off by the notification's „Aus“ (not by the app). Set only there; every
     * `configure` of the app clears it. The app adopts an „Aus“ only with this flag, so a status
     * read before its own `configure(enabled=true)` cannot switch it off again.
     */
    val offByUser: Boolean = false,
    /**
     * Developer mode of the app (WP148), mirrored by `devMode` on the wake channel: the wake
     * engine (no database) records audio only while this is set. Not part of `configure`.
     */
    val devMode: Boolean = false,
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
            detector = (args?.get("detector") as? String)?.takeIf { it in DETECTORS } ?: detector,
            pausedUntilMs = if (on) pausedUntilMs else 0L,
            offByUser = if (args?.containsKey("enabled") == true) false else offByUser,
            devMode = devMode,
        )
    }
}

/** Accepted values of the setting `detector` (WP129). */
val DETECTORS = setOf("auto", "templates", "model")

/** Where a wake word hit goes (WP93). */
enum class HitRoute { CHAT, OVERLAY }

/**
 * WP93: what the main app's Dart side reports about its chat (process-wide, the service and the
 * main engine live in one process). [visible] only while the main screen is resumed, its route
 * is the top one and nothing (dialog, sheet, settings) is above it. [owned]: the chat listens on
 * a hit; the service stays quiet until `chatDone`.
 */
object ChatState {
    /** The raw report from Dart; [visible] derives from it, so the lifecycle order never matters. */
    @Volatile var reported = false
    @Volatile var owned = false

    /** While the station is up the chat is never visible (WP99), whatever Dart reported. */
    val visible: Boolean get() = reported && !StationState.active

    /**
     * Dart reports whether the chat is visible. While the station is up it never is (WP99): the
     * wake word opens the overlay, not the chat behind the station.
     */
    fun report(isVisible: Boolean) {
        reported = isVisible
    }

    /** The main screen leaves the foreground (activity paused). */
    fun paused() {
        reported = false
    }

    /**
     * The chat reports its turn as over. Only effective if it owns the hit: a chat that lost the
     * hit to the overlay (late answer) must not reopen the service microphone. Returns whether
     * the service is to listen again.
     */
    @Synchronized
    fun release(): Boolean {
        val was = owned
        owned = false
        return was
    }

    @Synchronized
    fun own() {
        owned = true
    }

    @Synchronized
    fun reset() {
        reported = false
        owned = false
    }
}

/** Timer seam of [ChatHitArbiter] (the service posts on its main handler; tests use a fake). */
interface HitScheduler {
    fun postDelayed(delayMs: Long, task: Runnable)

    fun cancel(task: Runnable)
}

/**
 * WP93: asks the chat about a hit and decides exactly once: the chat takes it (answer `true` in
 * time) or the overlay opens (refusal, error, timeout). A late answer changes nothing, so there
 * are never two listeners. Runs on the main thread, so the decision is made before the chat's
 * next channel call (taking the audio) is handled.
 */
class ChatHitArbiter(
    private val scheduler: HitScheduler,
    private val openOverlay: () -> Unit,
    private val chatAccepted: () -> Unit,
    private val answerMs: Long = ANSWER_MS,
) {
    fun begin(ask: ((Any?) -> Unit) -> Unit) {
        var settled = false
        val timeout = Runnable {
            if (settled) return@Runnable
            settled = true
            openOverlay()
        }
        scheduler.postDelayed(answerMs, timeout)
        ask { reply ->
            if (settled) return@ask
            settled = true
            scheduler.cancel(timeout)
            if (reply == true) {
                ChatState.own()
                chatAccepted()
            } else {
                openOverlay()
            }
        }
    }

    companion object {
        const val ANSWER_MS = 1_500L
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
     * Whether the engine's `startMic`/`stopMic` are ignored: only while a hit's audio is collected
     * from a microphone that is really open (a stale flag must not make the wake word deaf).
     */
    fun ignoresMicCalls(capturing: Boolean, micOpen: Boolean): Boolean = capturing && micOpen

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
     * (another recording is active), else `null`. Every `MODE_IN_COMMUNICATION` counts as a call
     * (WP165: the app itself never sets that mode).
     */
    fun conflict(audioMode: Int, foreignRecording: Boolean): String? = when {
        audioMode == MODE_IN_CALL ||
            audioMode == MODE_IN_COMMUNICATION ||
            audioMode == MODE_CALL_SCREENING -> "call"
        foreignRecording -> "recording"
        else -> null
    }

    /**
     * Whether the microphone is closed by the service itself, not only by Dart: any conflict.
     * WP149: during a hand-over overlap ([handoffOverlap]: the hit was taken with the capture kept
     * open) a `recording` is the app's own new `AudioRecord` (same process, other session) and
     * does not close it, else the tail ends early and a hole remains; a `call` always does.
     * Known cost: the service cannot tell the app's session from a truly foreign one here, so a
     * foreign recording that starts inside the overlap is tolerated until the first app frame
     * or the guard ([WakeWordService.OVERLAP_GUARD_MS], 2.5 s) ends it; then `recording` closes
     * as usual. Telling them apart (the app reporting its session via [AppVoice]) is a follow-up.
     */
    fun closesMicFor(conflict: String?, handoffOverlap: Boolean = false): Boolean =
        conflict == "call" || (conflict == "recording" && !handoffOverlap)

    /** WP149: the `wake-conflict` log line (numbers and codes only). */
    fun conflictLog(conflict: String?, handoffOverlap: Boolean, closes: Boolean): String =
        "wake-conflict reason=${conflict ?: "none"} handoff=${if (handoffOverlap) "kept" else "none"} " +
            "action=${if (closes) "close" else "keep"}"

    /** Whether `startMic` of Dart may open the microphone while the last [conflict] holds. */
    fun mayStartMic(conflict: String?): Boolean = !closesMicFor(conflict)

    /**
     * WP93: where a confirmed hit goes. The chat of the main app when it is visible (flag set by
     * Dart, cleared natively on pause), the device is unlocked and the main engine can be asked;
     * everything else is the overlay with a new conversation (K41).
     */
    fun routeHit(
        chatVisible: Boolean,
        locked: Boolean,
        hostAvailable: Boolean,
        stationActive: Boolean = false,
    ): HitRoute =
        if (chatVisible && !stationActive && !locked && hostAvailable) HitRoute.CHAT else HitRoute.OVERLAY

    /**
     * WP93: whether the activity asking for the hit's audio gets it. The overlay always; the main
     * app only for a hit its chat owns (else it would take the overlay's audio).
     */
    fun mayTakeHandoff(isMainApp: Boolean, chatOwned: Boolean): Boolean = !isMainApp || chatOwned

    /** Debug builds only: the `debugHit` shortcut ([flags] of ApplicationInfo, FLAG_DEBUGGABLE = 2). */
    fun allowsDebugHit(flags: Int): Boolean = flags and 2 != 0

    /**
     * The stop reason the service stores for a failure [reported] by the Dart engine. The missing
     * model keeps its own reason (the status names it); every other failure is `engine-failed`.
     */
    fun failureReason(reported: String?): String =
        if (reported == "modelMissing") "modelMissing" else "engine-failed"

    /**
     * WP171: whether the Dart engine's `stage2Gap` [reason] means that stage 2 cannot decide (no
     * recognition model) or has no sequences of the voice (it has to be enrolled again). `null`
     * (or anything unknown) clears the notice.
     */
    fun stage2GapActive(reason: String?): Boolean = reason == "model_missing" || reason == "no_sequences"

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
    class Taken(val pcm: ByteArray, val wakeEnd: Int, val capturedMs: Long, val lastSampleAtMs: Long = 0)

    private var pcm: ByteArray? = null
    private var wakeEnd = 0
    private var at = 0L
    private var capturing = false
    private var lastSampleAt = 0L
    private var tail = java.io.ByteArrayOutputStream()

    @Synchronized
    fun put(pcm: ByteArray, nowMs: Long, wakeEnd: Int = 0) {
        this.pcm = pcm
        this.wakeEnd = wakeEnd
        at = nowMs
        capturing = false
        lastSampleAt = 0L
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
    fun append(chunk: ByteArray, atMs: Long = 0) {
        if (!capturing) return
        if (atMs > 0) lastSampleAt = atMs
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
            Taken(p + extra, wakeEnd, extra.size / 2 * 1000L / 16_000, lastSampleAt)
        } else {
            null
        }
    }

    /**
     * WP146: like [take], but the capture stays open. What the service records from now on is
     * collected for [finish], so the app's own microphone can open and deliver its first frame
     * before the service stops: no hole between the two recordings. `null` (and the capture
     * ends) if none or stale.
     */
    @Synchronized
    fun takeKeepingOpen(nowMs: Long): Taken? {
        val p = pcm
        pcm = null
        val extra = tail.toByteArray()
        tail = java.io.ByteArrayOutputStream()
        if (p == null || nowMs - at > MAX_AGE_MS) {
            capturing = false
            return null
        }
        return Taken(p + extra, wakeEnd, extra.size / 2 * 1000L / 16_000, lastSampleAt)
    }

    /**
     * WP146: ends a capture kept open by [takeKeepingOpen]; returns what was recorded since (the
     * `pcm` of the result, `wakeEnd` 0) with the time of its last sample. `null` if no capture
     * was open.
     */
    @Synchronized
    fun finish(): Taken? {
        val was = capturing || tail.size() > 0
        val extra = tail.toByteArray()
        val last = lastSampleAt
        capturing = false
        tail = java.io.ByteArrayOutputStream()
        lastSampleAt = 0L
        return if (was) Taken(extra, 0, extra.size / 2 * 1000L / 16_000, last) else null
    }

    /** WP146: no more audio is collected (the microphone closed), what was collected stays for [finish]. */
    @Synchronized
    fun stopCapture() {
        capturing = false
    }

    /** Whether a hit waits for the overlay. */
    @Synchronized
    fun pending(): Boolean = pcm != null

    @Synchronized
    fun clear() {
        pcm = null
        capturing = false
        lastSampleAt = 0L
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

/**
 * WP146: whether the app records or is about to (a voice request, its answer, a follow-up
 * window), reported by every Dart engine of the process with its own [source]. The wake-word
 * service does not open its microphone while this is on and for [QUIET_MS] after it ended: two
 * `VOICE_RECOGNITION` recordings at once can degrade the app's audio (the conflict watcher closes
 * the service only afterwards).
 */
object AppVoice {
    const val QUIET_MS = 700L

    /**
     * Fail-safe: a source that reported "active" and never "inactive" (hanging phase, lost call)
     * stops counting after this long, else the service would stay deaf. Longer than a request
     * with a long answer and the follow-up window.
     */
    const val MAX_ACTIVE_MS = 180_000L

    private val sources = mutableMapOf<String, Long>()
    private var endedAt = Long.MIN_VALUE / 2

    @Synchronized
    fun set(source: String, active: Boolean, nowMs: Long) {
        if (active) {
            // Reporting again renews the time (a new request of the same engine).
            sources[source] = nowMs
        } else if (sources.remove(source) != null && sources.isEmpty()) {
            endedAt = nowMs
        }
    }

    @Synchronized
    fun active(nowMs: Long): Boolean {
        prune(nowMs)
        return sources.isNotEmpty()
    }

    /**
     * How long the service waits before it opens its microphone: 0 = now, [WAIT_FOR_APP] = the
     * app records (ask again when it reports the end, at the latest after [MAX_ACTIVE_MS]), else
     * the rest of the quiet time in ms.
     */
    @Synchronized
    fun waitMs(nowMs: Long): Long {
        prune(nowMs)
        return when {
            sources.isNotEmpty() -> WAIT_FOR_APP
            else -> (endedAt + QUIET_MS - nowMs).coerceIn(0L, QUIET_MS)
        }
    }

    const val WAIT_FOR_APP = -1L

    private fun prune(nowMs: Long) {
        val it = sources.entries.iterator()
        while (it.hasNext()) {
            val e = it.next()
            if (nowMs - e.value >= MAX_ACTIVE_MS) {
                it.remove()
                endedAt = e.value + MAX_ACTIVE_MS
            }
        }
    }

    @Synchronized
    fun reset() {
        sources.clear()
        endedAt = Long.MIN_VALUE / 2
    }
}
