package app.wendelin

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [CentralAudioHub] (WP180, ADR 0024).
 */
class CentralAudioHubTest {

    @Test
    fun tracksSubscribers() {
        val hub = CentralAudioHub()
        assertFalse(hub.hasSubscribers())
        assertFalse(hub.hasSubscriber(AudioSubscriberKind.WAKE))

        val wakeId = hub.subscribe(AudioSubscriberKind.WAKE, onChunk = {})
        assertTrue(hub.hasSubscribers())
        assertTrue(hub.hasSubscriber(AudioSubscriberKind.WAKE))
        assertEquals(1, hub.subscriberCount)

        val enrollId = hub.subscribe(AudioSubscriberKind.ENROLL, onChunk = {})
        assertTrue(hub.hasSubscriber(AudioSubscriberKind.ENROLL))
        assertEquals(2, hub.subscriberCount)

        assertTrue(hub.unsubscribe(wakeId))
        assertFalse(hub.hasSubscriber(AudioSubscriberKind.WAKE))
        assertTrue(hub.hasSubscriber(AudioSubscriberKind.ENROLL))

        hub.unsubscribeKind(AudioSubscriberKind.ENROLL)
        assertFalse(hub.hasSubscribers())
    }

    @Test
    fun dispatchesToWakeWhenAlone() {
        val hub = CentralAudioHub()
        val wakeChunks = mutableListOf<ByteArray>()
        hub.subscribe(AudioSubscriberKind.WAKE, onChunk = { wakeChunks.add(it) })

        val chunk = ByteArray(64) { 1 }
        hub.dispatchChunk(chunk)

        assertEquals(1, wakeChunks.size)
        assertArrayEquals(chunk, wakeChunks.first())
        assertEquals(64, hub.ringBuffer.filled)
    }

    @Test
    fun suppressesWakeWhenSessionIsActive() {
        val hub = CentralAudioHub()
        val wakeChunks = mutableListOf<ByteArray>()
        val sessionChunks = mutableListOf<ByteArray>()

        hub.subscribe(AudioSubscriberKind.WAKE, onChunk = { wakeChunks.add(it) })
        val sessionId = hub.subscribe(AudioSubscriberKind.SESSION, onChunk = { sessionChunks.add(it) })

        val chunk1 = ByteArray(64) { 2 }
        hub.dispatchChunk(chunk1)

        // Session received it, wake was suppressed!
        assertEquals(0, wakeChunks.size)
        assertEquals(1, sessionChunks.size)
        assertArrayEquals(chunk1, sessionChunks.first())

        // End session -> wake resumes
        hub.unsubscribe(sessionId)

        val chunk2 = ByteArray(64) { 3 }
        hub.dispatchChunk(chunk2)

        assertEquals(1, wakeChunks.size)
        assertArrayEquals(chunk2, wakeChunks.first())
    }

    @Test
    fun suppressesWakeWhenEnrollIsActive() {
        val hub = CentralAudioHub()
        val wakeChunks = mutableListOf<ByteArray>()
        val enrollChunks = mutableListOf<ByteArray>()

        hub.subscribe(AudioSubscriberKind.WAKE, onChunk = { wakeChunks.add(it) })
        val enrollId = hub.subscribe(AudioSubscriberKind.ENROLL, onChunk = { enrollChunks.add(it) })

        val chunk1 = ByteArray(64) { 4 }
        hub.dispatchChunk(chunk1)

        assertEquals(0, wakeChunks.size)
        assertEquals(1, enrollChunks.size)
        assertArrayEquals(chunk1, enrollChunks.first())

        hub.unsubscribe(enrollId)

        val chunk2 = ByteArray(64) { 5 }
        hub.dispatchChunk(chunk2)

        assertEquals(1, wakeChunks.size)
        assertArrayEquals(chunk2, wakeChunks.first())
    }

    @Test
    fun providesPreRollFromRingBuffer() {
        val hub = CentralAudioHub()
        // Feed 100 ms of audio (3200 bytes)
        val data = ByteArray(3200) { 7 }
        hub.dispatchChunk(data)

        val preRoll = hub.getPreRollMs(50)
        assertEquals(1600, preRoll.size)
        assertTrue(preRoll.all { it == 7.toByte() })
    }

    @Test
    fun dispatchesErrorsToSubscribers() {
        val hub = CentralAudioHub()
        var errorSeen: Throwable? = null
        hub.subscribe(
            AudioSubscriberKind.SESSION,
            onChunk = {},
            onError = { errorSeen = it },
        )

        val boom = IllegalStateException("mic failed")
        hub.dispatchError(boom)

        assertEquals(boom, errorSeen)
    }

    @Test
    fun clearResetsRingBufferAndSubscribers() {
        val hub = CentralAudioHub()
        hub.subscribe(AudioSubscriberKind.WAKE, onChunk = {})
        hub.dispatchChunk(ByteArray(100) { 1 })

        hub.clear()
        assertFalse(hub.hasSubscribers())
        assertEquals(0, hub.ringBuffer.filled)
    }

    @Test
    fun supportsMultipleSimultaneousSessions() {
        val hub = CentralAudioHub()
        val session1Chunks = mutableListOf<ByteArray>()
        val session2Chunks = mutableListOf<ByteArray>()

        val sub1 = hub.subscribe(AudioSubscriberKind.SESSION, onChunk = { session1Chunks.add(it) })
        val sub2 = hub.subscribe(AudioSubscriberKind.SESSION, onChunk = { session2Chunks.add(it) })

        assertEquals(2, hub.subscriberCount)

        val chunk1 = ByteArray(64) { 10 }
        hub.dispatchChunk(chunk1)

        assertEquals(1, session1Chunks.size)
        assertEquals(1, session2Chunks.size)
        assertArrayEquals(chunk1, session1Chunks.first())
        assertArrayEquals(chunk1, session2Chunks.first())

        // Unsubscribe sub1, sub2 still receives
        assertTrue(hub.unsubscribe(sub1))
        assertEquals(1, hub.subscriberCount)

        val chunk2 = ByteArray(64) { 20 }
        hub.dispatchChunk(chunk2)

        assertEquals(1, session1Chunks.size)
        assertEquals(2, session2Chunks.size)
        assertArrayEquals(chunk2, session2Chunks.last())
    }
}

