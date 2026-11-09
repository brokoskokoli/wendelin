package app.wendelin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [WakeEngineFeed] (WP189): the tap counts in the frame of the wake listener's stream position, so
 * a hit hands over only the frames that were still on their way, never audio from before the hit.
 * The wiring is the service's own ([WakeEngineFeed.attach], [WakeEngineFeed.onStartMic]).
 */
class WakeEngineFeedTest {
    /** 100 ms chunks like the central recording; sample value = chunk index. */
    private fun chunk(i: Int) = ByteArray(3200) { n -> if (n % 2 == 0) i.toByte() else 0 }

    /** The service's wiring; the "Dart side" accepts the chunks of its current token, like `ServiceAudioInput`. */
    private class Wiring(val feed: WakeEngineFeed = WakeEngineFeed(), val hub: CentralAudioHub = CentralAudioHub()) {
        var dartToken = 0L
        var dart = 0L
        var requests = 0

        init {
            feed.attach(hub) { args ->
                if (args["token"] == dartToken) dart += (args["pcm"] as ByteArray).size / 2
            }
        }

        /** The listener (re)starts its stream: new token, position 0, `startMic` to the service. */
        fun listenerStarts(token: Long, ignored: Boolean = false) {
            dartToken = token
            dart = 0
            feed.onStartMic(token, ignored) { requests++ }
        }
    }

    @Test
    fun aHitAfterADialogAndAResumeGetsOnlyTheFramesOnTheirWay() {
        val w = Wiring()
        var i = 0
        w.listenerStarts(1)
        repeat(50) { w.hub.dispatchChunk(chunk(i++)) }
        // A dialog: the microphone keeps running (WP180), the wake stream is held back.
        val session = w.hub.subscribe(AudioSubscriberKind.SESSION, onChunk = {})
        repeat(80) { w.hub.dispatchChunk(chunk(i++)) }
        w.hub.unsubscribe(session)
        // The listener resumes after the overlay: its position starts at 0 again.
        w.listenerStarts(2)
        repeat(20) { w.hub.dispatchChunk(chunk(i++)) }
        assertEquals(20L * 1600, w.dart)
        // The listener's pre-roll ends 2 chunks before the newest: only those 2 are handed over.
        val tail = w.feed.tap.tailAfter(w.dart - 2 * 1600)
        assertEquals(2 * 3200, tail.size)
        assertEquals((i - 2).toByte(), tail[0])
        assertEquals((i - 1).toByte(), tail[3200])
    }

    @Test
    fun anIgnoredStartMicStillStartsTheCountAgain() {
        val w = Wiring()
        w.listenerStarts(1)
        repeat(40) { w.hub.dispatchChunk(chunk(it)) }
        // While a hit's audio is collected the service ignores the call (WP68), the count restarts anyway.
        w.listenerStarts(2, ignored = true)
        assertEquals(1, w.requests)
        repeat(3) { w.hub.dispatchChunk(chunk(it)) }
        assertEquals(w.dart, w.feed.tap.sent)
        assertEquals(0, w.feed.tap.tailAfter(w.dart).size)
    }

    @Test
    fun chunksOfAnOlderStreamAreNotCountedByTheListener() {
        val w = Wiring()
        w.listenerStarts(1)
        repeat(5) { w.hub.dispatchChunk(chunk(it)) }
        // The service restarted (e.g. after release) while the listener still runs on token 1.
        w.feed.restart(0)
        repeat(3) { w.hub.dispatchChunk(chunk(it)) }
        assertEquals(5L * 1600, w.dart)
        assertFalse(w.feed.tap.sent == w.dart)
        assertTrue(w.feed.tap.tailAfter(w.dart).isEmpty())
    }
}
