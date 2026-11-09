package app.wendelin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [WakeEngineFeed] (WP189): the tap counts in the frame of the wake listener's stream position, so
 * a hit hands over only the frames that were still on their way, never audio from before the hit.
 */
class WakeEngineFeedTest {
    /** 100 ms chunks like the central recording; sample value = chunk index. */
    private fun chunk(i: Int) = ByteArray(3200) { n -> if (n % 2 == 0) i.toByte() else 0 }

    /** Wires [feed] into [hub] like the service; what the "Dart side" accepts (current token) is counted in [dart]. */
    private class Wiring(val feed: WakeEngineFeed, val hub: CentralAudioHub) {
        var dartToken = 0L
        var dart = 0L

        init {
            hub.subscribe(AudioSubscriberKind.WAKE, "wake-engine", onChunk = { pcm ->
                val args = feed.send(pcm)
                if (args["token"] == dartToken) dart += (args["pcm"] as ByteArray).size / 2
            })
        }

        /** The listener (re)starts: new token on both sides, position 0. */
        fun listenerStarts(token: Long) {
            dartToken = token
            dart = 0
            feed.restart(token)
        }
    }

    @Test
    fun aHitAfterADialogAndAResumeGetsOnlyTheFramesOnTheirWay() {
        val hub = CentralAudioHub()
        val w = Wiring(WakeEngineFeed(), hub)
        var i = 0
        w.listenerStarts(1)
        repeat(50) { hub.dispatchChunk(chunk(i++)) }
        // A dialog: the microphone keeps running (WP180), the wake stream is held back.
        val session = hub.subscribe(AudioSubscriberKind.SESSION, onChunk = {})
        repeat(80) { hub.dispatchChunk(chunk(i++)) }
        hub.unsubscribe(session)
        // The listener resumes after the overlay: its position starts at 0 again.
        w.listenerStarts(2)
        repeat(20) { hub.dispatchChunk(chunk(i++)) }
        assertEquals(20L * 1600, w.dart)
        // The listener's pre-roll ends 2 chunks before the newest: only those 2 are handed over.
        val tail = w.feed.tap.tailAfter(w.dart - 2 * 1600)
        assertEquals(2 * 3200, tail.size)
        assertEquals((i - 2).toByte(), tail[0])
        assertEquals((i - 1).toByte(), tail[3200])
    }

    @Test
    fun beforeWp189TheTapRanAheadAndHandedOverItsWholeBuffer() {
        // The old counting (every microphone chunk since the microphone opened) against the
        // listener's position after a resume: the full 3 s came back, the wake word again.
        val tap = WakeMicTap()
        repeat(150) { tap.onChunk(chunk(it)) }
        val listenerPos = 18L * 1600
        assertTrue(tap.tailAfter(listenerPos).size >= 3 * 16_000 * 2)
    }

    @Test
    fun eachChunkCarriesTheTokenItWasCountedUnder() {
        val feed = WakeEngineFeed()
        assertEquals(0L, feed.send(chunk(0))["token"])
        feed.restart(7)
        assertEquals(0L, feed.tap.sent)
        val args = feed.send(chunk(1))
        assertEquals(7L, args["token"])
        assertEquals(1600L, feed.tap.sent)
    }
}
