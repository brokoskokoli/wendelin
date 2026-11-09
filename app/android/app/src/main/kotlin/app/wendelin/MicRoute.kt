package app.wendelin

import java.util.concurrent.atomic.AtomicReference

/**
 * Pure logic of the microphone choice in the central recording (WP188 part D, K149): which device
 * is wanted and whether the running recording must change. No Android types, tested on the JVM.
 */
internal object MicRoute {
    /**
     * Raw `AudioDeviceInfo` types that part D does not set: Bluetooth SCO (7) and LE (26) belong
     * to the dialog only (part E), so they count as "system" here.
     */
    private val DEFERRED_TYPES = setOf(7, 26)

    /**
     * The key of the device to prefer, `null` = system default: the selected device if it is
     * connected as an input and not deferred, else `null` (not chosen, gone, Bluetooth).
     */
    fun target(selected: AudioDeviceEntry?, devices: List<AudioDeviceDesc>): String? {
        val key = selected?.key ?: return null
        val d = devices.firstOrNull {
            AudioDevicePick.typeName(it, AudioDevicePick.INPUT) != null && AudioDevicePick.keyOf(it) == key
        } ?: return null
        return if (d.type in DEFERRED_TYPES) null else key
    }

    /** What to do with a running recording on [active] (key, `null` = system) given a [target]. */
    enum class Action { KEEP, SWITCH, CANCEL_PENDING }

    /**
     * [pending]: a switch is already under way to that key (`hasPending`, key may be `null` for
     * "to the system"). Same state as before = nothing happens (the system path stays untouched).
     */
    fun decide(active: String?, hasPending: Boolean, pending: String?, target: String?): Action = when {
        hasPending && pending == target -> Action.KEEP
        hasPending && target == active -> Action.CANCEL_PENDING
        hasPending -> Action.SWITCH
        active == target -> Action.KEEP
        else -> Action.SWITCH
    }
}

/** One started recording of [SwitchingReader]: the `AudioRecord` (or a fake in tests). */
internal interface MicTrack : PcmReader {
    /** Key of the preferred device, `null` = system default route. */
    val key: String?

    /** Audio session of the recording (tells it from foreign ones). */
    val sessionId: Int

    /** Stops and frees the recording (idempotent). */
    fun release()
}

/**
 * A [PcmReader] that can move to another recording without a hole or a doubled frame.
 *
 * [offer] hands over a started candidate (any thread). The reading thread keeps reading the old
 * recording until the candidate delivers data. At that moment it throws away what the candidate
 * has buffered so far (that time span is already in the old stream), delivers what the old one
 * still has, and reads on from the candidate. The stream the subscribers see is therefore one
 * continuous sequence of samples; only the candidate's own head start is dropped. A candidate
 * that stays silent for [giveUpMs] or fails is released and the old recording goes on.
 */
internal class SwitchingReader(
    first: MicTrack,
    private val nowMs: () -> Long = System::currentTimeMillis,
    private val giveUpMs: Long = 3000L,
    private val onEvent: (String) -> Unit = {},
) : PcmReader {
    private class Pending(val track: MicTrack, val sinceMs: Long)

    @Volatile private var active: MicTrack = first
    private val pending = AtomicReference<Pending?>(null)
    private val scratch = ByteArray(SCRATCH_BYTES)
    private var carry = ByteArray(0)
    private var carryPos = 0

    val activeKey: String? get() = active.key
    val hasPending: Boolean get() = pending.get() != null
    val pendingKey: String? get() = pending.get()?.track?.key

    /** Session ids of the recordings that are open now (during a switch there are two). */
    val sessionIds: Set<Int>
        get() = setOfNotNull(active.sessionId, pending.get()?.track?.sessionId).filter { it != 0 }.toSet()

    /** Offers a started [track]; a candidate waiting before is released. */
    fun offer(track: MicTrack) {
        pending.getAndSet(Pending(track, nowMs()))?.track?.release()
    }

    /** Drops the candidate (the wish went back to what runs). */
    fun cancelPending() {
        pending.getAndSet(null)?.track?.release()
    }

    /** Frees both recordings (end of the reading thread). */
    fun releaseAll() {
        cancelPending()
        active.release()
    }

    override fun read(buf: ByteArray, off: Int, len: Int): Int {
        if (carryPos >= carry.size) settle()
        if (carryPos < carry.size) {
            val n = minOf(len, carry.size - carryPos)
            System.arraycopy(carry, carryPos, buf, off, n)
            carryPos += n
            return n
        }
        return active.read(buf, off, len)
    }

    override fun readAvailable(buf: ByteArray, off: Int, len: Int): Int = active.readAvailable(buf, off, len)

    /**
     * Moves to the candidate if it delivers. What the old recording still had buffered goes to
     * [carry] (more than one read may hold) and is delivered first.
     */
    private fun settle() {
        val p = pending.get() ?: return
        val probe = try {
            p.track.readAvailable(scratch, 0, scratch.size)
        } catch (e: RuntimeException) {
            -1
        }
        if (probe < 0 || (probe == 0 && nowMs() - p.sinceMs > giveUpMs)) {
            if (pending.compareAndSet(p, null)) p.track.release()
            onEvent(if (probe < 0) "switch-failed" else "switch-silent")
            return
        }
        if (probe == 0) return
        // The candidate delivers. Its buffered head start duplicates the old stream: drop it
        // first, then take the rest of the old stream, so nothing of the old one is lost.
        drain(p.track) { }
        val old = active
        val tail = java.io.ByteArrayOutputStream()
        drain(old) { tail.write(scratch, 0, it) }
        // A newer offer may have replaced p meanwhile: then p is already released, stay.
        if (!pending.compareAndSet(p, null)) {
            carry = tail.toByteArray()
            carryPos = 0
            return
        }
        active = p.track
        old.release()
        carry = tail.toByteArray()
        carryPos = 0
        onEvent("switched")
    }

    /** Reads what [track] has right now, [sink] gets each piece (of [scratch]). */
    private fun drain(track: PcmReader, sink: (Int) -> Unit) {
        var guard = 0
        while (guard++ < MAX_DRAIN) {
            val n = track.readAvailable(scratch, 0, scratch.size)
            if (n <= 0) break
            sink(n)
        }
    }

    private companion object {
        const val SCRATCH_BYTES = 3200
        const val MAX_DRAIN = 2000
    }
}
