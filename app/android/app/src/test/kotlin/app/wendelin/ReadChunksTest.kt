package app.wendelin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** WP149: the unfinished chunk is delivered at the hand-over stop (no hole before the first app frame). */
class ReadChunksTest {
    /** Gives [script] bytes per blocking read; the stop flag flips after [stopAfterReads] reads. */
    private class Fake(val script: List<Int>, val stopAfterReads: Int, val buffered: Int) : PcmReader {
        var reads = 0
        var running = true
        var flush = true
        val out = mutableListOf<ByteArray>()

        override fun read(buf: ByteArray, off: Int, len: Int): Int {
            val n = minOf(script[reads], len)
            for (i in 0 until n) buf[off + i] = 1
            reads++
            if (reads >= stopAfterReads) running = false
            return n
        }

        override fun readAvailable(buf: ByteArray, off: Int, len: Int): Int {
            val n = minOf(buffered, len)
            for (i in 0 until n) buf[off + i] = 2
            return n
        }

        fun run(chunkBytes: Int) =
            readChunks(this, chunkBytes, { running }, { flush }) { out += it }
    }

    @Test
    fun theUnfinishedChunkIsDeliveredWithWhatIsBuffered() {
        // 100-byte chunks: one full chunk, then 40 bytes read, then stop; 30 bytes are buffered.
        val f = Fake(listOf(100, 40), stopAfterReads = 2, buffered = 30)
        f.run(100)
        assertEquals(listOf(100, 70), f.out.map { it.size })
        assertEquals(2, f.out[1][40].toInt())
    }

    @Test
    fun anOddByteIsNotDelivered() {
        val f = Fake(listOf(41), stopAfterReads = 1, buffered = 0)
        f.run(100)
        assertEquals(listOf(40), f.out.map { it.size })
    }

    @Test
    fun aChunkCompletedByTheLastReadIsDelivered() {
        val f = Fake(listOf(100), stopAfterReads = 1, buffered = 0)
        f.run(100)
        assertEquals(listOf(100), f.out.map { it.size })
    }

    @Test
    fun withoutFlushTheUnfinishedChunkIsDropped() {
        val f = Fake(listOf(100, 40), stopAfterReads = 2, buffered = 30)
        f.flush = false
        f.run(100)
        assertEquals(listOf(100), f.out.map { it.size })
        assertTrue(f.out.all { it.all { b -> b.toInt() == 1 } })
    }
}
