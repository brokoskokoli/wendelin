package app.wendelin

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [AudioRingBuffer] (WP180, ADR 0024).
 */
class AudioRingBufferTest {

    @Test(expected = IllegalArgumentException::class)
    fun rejectsCapacityBelowMinimum() {
        AudioRingBuffer(AudioRingBuffer.MIN_CAPACITY_BYTES - 1)
    }

    @Test
    fun startsEmpty() {
        val ring = AudioRingBuffer()
        assertEquals(0, ring.filled)
        assertEquals(0L, ring.durationMs)
        assertEquals(AudioRingBuffer.DEFAULT_CAPACITY_BYTES, ring.capacityBytes)
        assertArrayEquals(ByteArray(0), ring.readRecent(100))
        assertArrayEquals(ByteArray(0), ring.readRecentMs(100))
    }

    @Test
    fun appendsAndReadsWithinCapacity() {
        val ring = AudioRingBuffer(AudioRingBuffer.MIN_CAPACITY_BYTES)
        val data = ByteArray(64) { it.toByte() }
        ring.append(data)

        assertEquals(64, ring.filled)
        assertEquals(2L, ring.durationMs) // 64 bytes / 32 bytes/ms = 2 ms
        assertArrayEquals(data, ring.readRecent(64))
    }

    @Test
    fun readsPartialRecent() {
        val ring = AudioRingBuffer(AudioRingBuffer.MIN_CAPACITY_BYTES)
        val data = ByteArray(100) { (it + 1).toByte() }
        ring.append(data)

        // Read last 20 bytes
        val recent = ring.readRecent(20)
        assertEquals(20, recent.size)
        val expected = data.copyOfRange(80, 100)
        assertArrayEquals(expected, recent)
    }

    @Test
    fun wrapsAroundAndDiscardsOldest() {
        val cap = AudioRingBuffer.MIN_CAPACITY_BYTES // 160,000 bytes
        val ring = AudioRingBuffer(cap)

        // Fill with sequence 1s
        val chunk1 = ByteArray(cap - 100) { 1 }
        ring.append(chunk1)
        assertEquals(cap - 100, ring.filled)

        // Append 200 bytes of sequence 2s (causes wrap-around of 100 bytes)
        val chunk2 = ByteArray(200) { 2 }
        ring.append(chunk2)
        assertEquals(cap, ring.filled)

        // Last 200 bytes must be all 2s
        val recent200 = ring.readRecent(200)
        assertTrue(recent200.all { it == 2.toByte() })

        // First (cap - 200) bytes must be 1s
        val all = ring.readRecent(cap)
        assertEquals(cap, all.size)
        assertTrue(all.copyOfRange(0, cap - 200).all { it == 1.toByte() })
        assertTrue(all.copyOfRange(cap - 200, cap).all { it == 2.toByte() })
    }

    @Test
    fun handlesAppendLargerThanCapacity() {
        val cap = AudioRingBuffer.MIN_CAPACITY_BYTES
        val ring = AudioRingBuffer(cap)

        val large = ByteArray(cap + 500) { (it % 120).toByte() }
        ring.append(large)

        assertEquals(cap, ring.filled)
        val expected = large.copyOfRange(500, large.size)
        assertArrayEquals(expected, ring.readRecent(cap))
    }

    @Test
    fun readRecentMsCalculatesBytesCorrectly() {
        val ring = AudioRingBuffer(AudioRingBuffer.MIN_CAPACITY_BYTES)
        // 100 ms = 3200 bytes
        val data = ByteArray(3200) { 42 }
        ring.append(data)

        val read = ring.readRecentMs(50) // 50 ms = 1600 bytes
        assertEquals(1600, read.size)
        assertTrue(read.all { it == 42.toByte() })
    }

    @Test
    fun clearsAndZeroesMemory() {
        val ring = AudioRingBuffer(AudioRingBuffer.MIN_CAPACITY_BYTES)
        ring.append(ByteArray(320) { 99 })
        assertEquals(320, ring.filled)

        ring.clear()
        assertEquals(0, ring.filled)
        assertEquals(0L, ring.durationMs)
        assertArrayEquals(ByteArray(0), ring.readRecent(100))
    }

    @Test
    fun alignsToWhole16BitSamples() {
        val ring = AudioRingBuffer(AudioRingBuffer.MIN_CAPACITY_BYTES)
        // Odd byte count should be truncated to even
        ring.append(ByteArray(15) { 7 })
        assertEquals(14, ring.filled)

        val oddRead = ring.readRecent(5)
        assertEquals(4, oddRead.size)
    }
}
