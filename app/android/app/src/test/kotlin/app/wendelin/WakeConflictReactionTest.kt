package app.wendelin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** WP149: how the service reacts to conflict reports during the hand-over overlap. */
class WakeConflictReactionTest {
    private class Sched : HitScheduler {
        val tasks = mutableListOf<Runnable>()
        var delay = 0L

        override fun postDelayed(delayMs: Long, task: Runnable) {
            delay = delayMs
            tasks += task
        }

        override fun cancel(task: Runnable) {
            tasks -= task
        }

        fun fire() = tasks.toList().also { tasks.clear() }.forEach { it.run() }
    }

    private class Rig {
        val sched = Sched()
        val guard = TimedGuard(sched)
        var stops = 0
        val lines = mutableListOf<String>()
        val reaction = WakeConflictReaction(guard, { stops++ }, { lines += it })
        var timedOut = 0

        /** The take with the capture kept open (as `handoffKept` does). */
        fun beginOverlap() = guard.arm(2500L) { timedOut++ }
    }

    @Test
    fun ownRecordingInTheOverlapKeepsTheMicrophone() {
        val r = Rig()
        r.beginOverlap()
        assertFalse(r.reaction.react("recording"))
        assertEquals(0, r.stops)
        assertEquals(listOf("wake-conflict reason=recording handoff=kept action=keep"), r.lines)
        assertEquals("recording", r.reaction.last)
    }

    @Test
    fun foreignRecordingOutsideTheOverlapClosesTheMicrophone() {
        val r = Rig()
        assertTrue(r.reaction.react("recording"))
        assertEquals(1, r.stops)
        assertEquals(listOf("wake-conflict reason=recording handoff=none action=close"), r.lines)
    }

    @Test
    fun aCallClosesItEvenInTheOverlap() {
        val r = Rig()
        r.beginOverlap()
        assertTrue(r.reaction.react("call"))
        assertEquals(1, r.stops)
        assertEquals("wake-conflict reason=call handoff=kept action=close", r.lines.single())
    }

    @Test
    fun theConflictAfterTheOverlapEndedClosesIt() {
        val r = Rig()
        r.beginOverlap()
        assertFalse(r.reaction.react("recording"))
        // The first frame arrived: the service disarms and stops the capture itself.
        r.guard.disarm()
        assertFalse(r.reaction.react(null))
        assertTrue(r.reaction.react("recording"))
        assertEquals(1, r.stops)
    }

    @Test
    fun theGuardTimeoutEndsTheOverlap() {
        val r = Rig()
        r.beginOverlap()
        assertEquals(2500L, r.sched.delay)
        assertTrue(r.guard.armed)
        r.sched.fire()
        assertEquals(1, r.timedOut)
        assertFalse(r.guard.armed)
        // A conflict that still holds closes the microphone once the overlap is over.
        assertTrue(r.reaction.react("recording"))
        assertEquals(1, r.stops)
    }

    @Test
    fun theGuardIsOneShotAndCanBeRearmedOrDisarmed() {
        val r = Rig()
        r.beginOverlap()
        r.beginOverlap()
        assertEquals(1, r.sched.tasks.size)
        r.guard.disarm()
        assertFalse(r.guard.armed)
        assertTrue(r.sched.tasks.isEmpty())
    }

    @Test
    fun resetForgetsTheReason() {
        val r = Rig()
        r.reaction.react("recording")
        r.reaction.reset()
        assertNull(r.reaction.last)
    }
}
