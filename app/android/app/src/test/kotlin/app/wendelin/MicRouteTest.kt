package app.wendelin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** WP188 part D: the microphone choice in the central recording and the hand-over without a hole. */
class MicRouteTest {
    private fun desc(type: Int, product: String, address: String = "", source: Boolean = true, sink: Boolean = false) =
        AudioDeviceDesc(type, product, address, source, sink)

    private val builtin = desc(15, "Phone", "")
    private val usb = desc(11, "USB Mic", "card=1;device=0")
    private val wired = desc(3, "Headset", "", source = true, sink = true)
    private val sco = desc(7, "Buds", "AA:BB:CC:DD:EE:FF")

    private fun entry(d: AudioDeviceDesc) = AudioDeviceEntry(AudioDevicePick.keyOf(d), "x", d.product)

    // --- Which device is wanted ---

    @Test
    fun systemChoiceIsNoTarget() {
        assertNull(MicRoute.target(null, listOf(builtin, usb)))
    }

    @Test
    fun chosenDeviceIsTargetWhileConnected() {
        assertEquals(AudioDevicePick.keyOf(usb), MicRoute.target(entry(usb), listOf(builtin, usb)))
    }

    @Test
    fun missingDeviceFallsBackToSystemAndComesBack() {
        val chosen = entry(usb)
        assertNull(MicRoute.target(chosen, listOf(builtin)))
        // Plugged in again: another address, the key is the same (USB address is not part of it).
        val again = usb.copy(address = "card=2;device=0")
        assertEquals(chosen.key, MicRoute.target(chosen, listOf(builtin, again)))
    }

    @Test
    fun bluetoothInputIsLeftToTheDialog() {
        assertNull(MicRoute.target(entry(sco), listOf(builtin, sco)))
        val le = desc(26, "LE Buds", "11:22:33:44:55:66")
        assertNull(MicRoute.target(entry(le), listOf(builtin, le)))
    }

    @Test
    fun anOutputOnlyDeviceIsNoMicrophone() {
        val speaker = desc(2, "Speaker", "", source = false, sink = true)
        val key = AudioDeviceEntry(AudioDevicePick.keyOf(speaker), "builtin_speaker", "Speaker")
        assertNull(MicRoute.target(key, listOf(builtin, speaker)))
    }

    @Test
    fun wiredHeadsetCountsForTheWakeWordToo() {
        assertEquals(AudioDevicePick.keyOf(wired), MicRoute.target(entry(wired), listOf(builtin, wired)))
    }

    @Test
    fun theServiceReadsTheChoiceFromTheStoreAfterARestart() {
        val kv = object : KeyValues {
            val m = HashMap<String, String?>()
            override fun getString(key: String) = m[key]
            override fun putString(key: String, value: String?) {
                m[key] = value
            }
        }
        AudioDeviceSelectionStore(kv).set(AudioDevicePick.INPUT, entry(usb))
        // A new store object over the same data = the service after a restart, no Flutter involved.
        val afterRestart = AudioDeviceSelectionStore(kv)
        assertEquals(AudioDevicePick.keyOf(usb), MicRoute.target(afterRestart.get(AudioDevicePick.INPUT), listOf(builtin, usb)))
        afterRestart.set(AudioDevicePick.INPUT, null)
        assertNull(MicRoute.target(afterRestart.get(AudioDevicePick.INPUT), listOf(builtin, usb)))
    }

    // --- Whether the running recording changes ---

    @Test
    fun sameRouteChangesNothing() {
        assertEquals(MicRoute.Action.KEEP, MicRoute.decide(null, false, null, null))
        assertEquals(MicRoute.Action.KEEP, MicRoute.decide("k", false, null, "k"))
    }

    @Test
    fun differentRouteSwitches() {
        assertEquals(MicRoute.Action.SWITCH, MicRoute.decide(null, false, null, "k"))
        assertEquals(MicRoute.Action.SWITCH, MicRoute.decide("k", false, null, null))
    }

    @Test
    fun aSwitchUnderWayIsNotRepeatedNorKept_whenTheWishGoesBack() {
        assertEquals(MicRoute.Action.KEEP, MicRoute.decide(null, true, "k", "k"))
        assertEquals(MicRoute.Action.CANCEL_PENDING, MicRoute.decide(null, true, "k", null))
        assertEquals(MicRoute.Action.SWITCH, MicRoute.decide(null, true, "k", "j"))
    }

    @Test
    fun ownRecordingsDuringTheSwitchAreNoForeignRecording() {
        val clients = listOf(RecordingClient(10, false), RecordingClient(11, false))
        assertNull(WakeConflictWatcher.reasonFor(0, setOf(10, 11), clients))
        assertEquals("recording", WakeConflictWatcher.reasonFor(0, setOf(10), clients))
    }

    // --- Hand-over without a hole ---

    /** Sample clock shared by the fake recordings: sample i is the same instant on every device. */
    private class Clock { var now = 0 }

    /** A recording that has the samples from `start + latency` on; the value of a sample is its index. */
    private class FakeTrack(
        private val clock: Clock,
        override val key: String?,
        override val sessionId: Int,
        start: Int,
        latency: Int = 0,
    ) : MicTrack {
        var pos = start + latency
        var released = false
        var failProbe = false

        override fun read(buf: ByteArray, off: Int, len: Int): Int {
            val want = len / 2
            if (pos + want > clock.now) clock.now = pos + want
            return take(buf, off, want)
        }

        override fun readAvailable(buf: ByteArray, off: Int, len: Int): Int {
            if (failProbe) return -1
            return take(buf, off, minOf(len / 2, maxOf(0, clock.now - pos)))
        }

        private fun take(buf: ByteArray, off: Int, samples: Int): Int {
            for (i in 0 until samples) {
                buf[off + 2 * i] = ((pos + i) and 0xff).toByte()
                buf[off + 2 * i + 1] = ((pos + i) shr 8).toByte()
            }
            pos += samples
            return samples * 2
        }

        override fun release() {
            released = true
        }
    }

    private fun samples(chunks: List<ByteArray>): List<Int> = chunks.flatMap { c ->
        (0 until c.size / 2).map { (c[2 * it].toInt() and 0xff) or ((c[2 * it + 1].toInt() and 0xff) shl 8) }
    }

    /** Reads [count] chunks of 1600 samples; [before] runs after chunk number n. */
    private fun run(
        reader: SwitchingReader,
        count: Int,
        hub: CentralAudioHub? = null,
        clock: Clock? = null,
        before: (Int) -> Unit,
    ): List<ByteArray> {
        val out = mutableListOf<ByteArray>()
        var i = 0
        readChunks(reader, 3200, { i < count }, { false }) {
            out += it
            hub?.dispatchChunk(it)
            // While the chunk is handled the microphone goes on: 25 ms pile up in its buffer.
            clock?.let { c -> c.now += 400 }
            i++
            before(i)
        }
        return out
    }

    private fun assertContinuous(all: List<Int>) {
        assertTrue(all.isNotEmpty())
        for (i in all.indices) assertEquals("sample $i", all[0] + i, all[i])
    }

    @Test
    fun handOverHasNoHoleAndNoDoubleFrame_neitherInTheStreamNorInTheRingBuffer() {
        val clock = Clock()
        val old = FakeTrack(clock, null, 10, 0)
        val reader = SwitchingReader(old)
        val hub = CentralAudioHub()
        var cand: FakeTrack? = null
        val chunks = run(reader, 12, hub, clock) { n ->
            // The new microphone starts at chunk 3 and needs 50 ms before the first sample.
            if (n == 3) {
                cand = FakeTrack(clock, "usb", 11, clock.now, latency = 800).also { reader.offer(it) }
                // Slow moment on the reading side: the new microphone has more buffered than one probe takes.
                clock.now += 3000
            }
        }
        assertEquals("usb", reader.activeKey)
        assertTrue(old.released)
        assertFalse(cand!!.released)
        assertContinuous(samples(chunks))
        // The ring buffer holds the same unbroken sequence.
        assertContinuous(samples(listOf(hub.ringBuffer.readRecent(hub.ringBuffer.filled))))
        assertEquals(12 * 3200, hub.ringBuffer.filled)
    }

    @Test
    fun theOldMicrophoneKeepsRunningUntilTheNewOneDelivers() {
        val clock = Clock()
        val old = FakeTrack(clock, null, 10, 0)
        val reader = SwitchingReader(old)
        var cand: FakeTrack? = null
        run(reader, 4, clock = clock) { n ->
            // A new microphone that stays silent for the next chunks.
            if (n == 1) cand = FakeTrack(clock, "usb", 11, clock.now, latency = 100_000).also { reader.offer(it) }
        }
        assertNull(reader.activeKey)
        assertFalse(old.released)
        assertTrue(reader.hasPending)
        assertEquals(setOf(10, 11), reader.sessionIds)
    }

    @Test
    fun aSilentCandidateIsGivenUpAndTheOldOneGoesOn() {
        val clock = Clock()
        val events = mutableListOf<String>()
        val old = FakeTrack(clock, null, 10, 0)
        val reader = SwitchingReader(old, nowMs = { clock.now / 16L }, giveUpMs = 300, onEvent = { events += it })
        val cand = FakeTrack(clock, "usb", 11, 0, latency = 1_000_000)
        reader.offer(cand)
        val chunks = run(reader, 6, clock = clock) { }
        assertTrue(cand.released)
        assertFalse(old.released)
        assertNull(reader.activeKey)
        assertEquals(listOf("switch-silent"), events)
        assertContinuous(samples(chunks))
    }

    @Test
    fun aFailingCandidateIsDroppedWithoutLosingAudio() {
        val clock = Clock()
        val old = FakeTrack(clock, null, 10, 0)
        val reader = SwitchingReader(old)
        val cand = FakeTrack(clock, "usb", 11, 0).also { it.failProbe = true }
        reader.offer(cand)
        val chunks = run(reader, 4, clock = clock) { }
        assertTrue(cand.released)
        assertNull(reader.activeKey)
        assertContinuous(samples(chunks))
    }

    @Test
    fun aNewerOfferReplacesAndReleasesTheOlderCandidate() {
        val clock = Clock()
        val reader = SwitchingReader(FakeTrack(clock, null, 10, 0))
        val a = FakeTrack(clock, "a", 11, 0, latency = 1_000_000)
        val b = FakeTrack(clock, "b", 12, 0)
        reader.offer(a)
        reader.offer(b)
        assertTrue(a.released)
        assertEquals("b", reader.pendingKey)
    }

    @Test
    fun deviceGoneAndBackSwitchesTwiceWithoutAHole() {
        val clock = Clock()
        val reader = SwitchingReader(FakeTrack(clock, "usb", 10, 0))
        val keys = mutableListOf<String?>()
        val chunks = run(reader, 20, clock = clock) { n ->
            // Unplugged: the system microphone takes over; plugged in again: back to the USB one.
            if (n == 3) reader.offer(FakeTrack(clock, null, 11, clock.now, latency = 400))
            if (n == 10) reader.offer(FakeTrack(clock, "usb", 12, clock.now, latency = 400))
            keys += reader.activeKey
        }
        assertEquals("usb", reader.activeKey)
        assertTrue(keys.contains(null))
        assertContinuous(samples(chunks))
    }

    @Test
    fun withoutAnOfferTheReaderIsTheTrackItself() {
        val clock = Clock()
        val reader = SwitchingReader(FakeTrack(clock, null, 10, 0))
        val chunks = run(reader, 5, clock = clock) { }
        assertContinuous(samples(chunks))
        assertNull(reader.activeKey)
        assertFalse(reader.hasPending)
        assertEquals(setOf(10), reader.sessionIds)
    }

    @Test
    fun releaseAllFreesBothRecordings() {
        val clock = Clock()
        val old = FakeTrack(clock, null, 10, 0)
        val cand = FakeTrack(clock, "usb", 11, 0, latency = 1_000_000)
        val reader = SwitchingReader(old)
        reader.offer(cand)
        reader.releaseAll()
        assertTrue(old.released && cand.released)
    }
}
