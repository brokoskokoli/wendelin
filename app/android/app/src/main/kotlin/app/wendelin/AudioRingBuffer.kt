package app.wendelin

/**
 * Continuous ring buffer for 16 kHz 16-bit mono PCM audio (WP180, ADR 0024, K145).
 *
 * Keeps at least 5–6 seconds of rolling audio history (default 6 seconds = 192,000 bytes).
 * Thread-safe for concurrent appends (audio capture thread) and reads (channel / subscriber dispatch).
 */
class AudioRingBuffer(val capacityBytes: Int = DEFAULT_CAPACITY_BYTES) {
    init {
        require(capacityBytes >= MIN_CAPACITY_BYTES) {
            "AudioRingBuffer capacity must be at least $MIN_CAPACITY_BYTES bytes (5 seconds)"
        }
    }

    private val ring = ByteArray(capacityBytes)
    private var writePos = 0
    private var filledBytes = 0

    val filled: Int
        @Synchronized get() = filledBytes

    val durationMs: Long
        @Synchronized get() = (filledBytes / BYTES_PER_MS).toLong()

    /**
     * Appends [length] bytes of [pcm] to the ring buffer.
     * Overwrites oldest bytes when capacity is exceeded.
     */
    @Synchronized
    fun append(pcm: ByteArray, length: Int = pcm.size) {
        val n = minOf(pcm.size, length) and 1.inv()
        if (n <= 0) return

        if (n >= capacityBytes) {
            System.arraycopy(pcm, n - capacityBytes, ring, 0, capacityBytes)
            writePos = 0
            filledBytes = capacityBytes
            return
        }

        val firstChunk = minOf(n, capacityBytes - writePos)
        System.arraycopy(pcm, 0, ring, writePos, firstChunk)
        val remaining = n - firstChunk
        if (remaining > 0) {
            System.arraycopy(pcm, firstChunk, ring, 0, remaining)
        }
        writePos = (writePos + n) % capacityBytes
        filledBytes = minOf(capacityBytes, filledBytes + n)
    }

    /**
     * Reads up to [byteCount] most recent bytes in chronological order (oldest first).
     * Returns an empty ByteArray if the buffer is empty or [byteCount] <= 0.
     */
    @Synchronized
    fun readRecent(byteCount: Int): ByteArray {
        val count = minOf(byteCount, filledBytes) and 1.inv()
        if (count <= 0) return ByteArray(0)

        val out = ByteArray(count)
        val startPos = (writePos - count + capacityBytes) % capacityBytes
        val firstChunk = minOf(count, capacityBytes - startPos)
        System.arraycopy(ring, startPos, out, 0, firstChunk)
        val remaining = count - firstChunk
        if (remaining > 0) {
            System.arraycopy(ring, 0, out, firstChunk, remaining)
        }
        return out
    }

    /** Reads the most recent [ms] milliseconds of audio. */
    @Synchronized
    fun readRecentMs(ms: Long): ByteArray {
        if (ms <= 0L) return ByteArray(0)
        val bytes = ms * BYTES_PER_MS
        val capped = minOf(bytes, capacityBytes.toLong()).toInt()
        return readRecent(capped)
    }

    /** Clears all held audio and zeroes memory. */
    @Synchronized
    fun clear() {
        ring.fill(0)
        writePos = 0
        filledBytes = 0
    }

    companion object {
        const val SAMPLE_RATE = 16_000
        const val BYTES_PER_SAMPLE = 2
        const val BYTES_PER_MS = SAMPLE_RATE * BYTES_PER_SAMPLE / 1000

        /** 5 seconds minimum capacity (160,000 bytes). */
        const val MIN_CAPACITY_BYTES = 5 * SAMPLE_RATE * BYTES_PER_SAMPLE

        /** 6 seconds default capacity (192,000 bytes). */
        const val DEFAULT_CAPACITY_BYTES = 6 * SAMPLE_RATE * BYTES_PER_SAMPLE
    }
}
