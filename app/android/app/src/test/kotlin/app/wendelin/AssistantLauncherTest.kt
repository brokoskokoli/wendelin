package app.wendelin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The session logic of B10 without Android: start, confirm, retry, finish. */
class AssistantLauncherTest {
    private val log = mutableListOf<String>()
    private val timers = mutableListOf<Pair<Long, () -> Unit>>()
    private var starts = 0
    private var ends = 0
    private var failures = 0
    private val retries = mutableListOf<Boolean>()

    private fun launcher() = AssistantLauncher(
        start = { retry ->
            starts++
            retries.add(retry)
            if (failures > 0) {
                failures--
                throw IllegalStateException("hidden session")
            }
        },
        schedule = { delay, block ->
            val entry = delay to block
            timers.add(entry)
            AssistantLauncher.Cancelable { timers.remove(entry) }
        },
        end = { ends++ },
        log = { log.add(it) },
    )

    private fun fireTimers() {
        val due = timers.toList()
        timers.clear()
        due.forEach { it.second() }
    }

    @Test
    fun overlayArrives_sessionFinishesOnce() {
        val l = launcher()
        l.onShow(1)
        assertEquals(1, starts)
        assertTrue(l.pending)
        l.onArrived()
        assertEquals(1, ends)
        assertFalse(l.pending)
        assertTrue(timers.isEmpty())
        // The finish hides the session: no second end.
        l.onHide()
        l.onArrived()
        assertEquals(1, ends)
        assertTrue(log.contains("session-finish reason=arrived attempts=1"))
    }

    @Test
    fun startThrows_retriedOnceWithFreshIntent() {
        failures = 1
        val l = launcher()
        l.onShow(0)
        assertEquals(2, starts)
        assertTrue(log.any { it.startsWith("assistant-start attempt=1 result=error error=IllegalStateException") })
        assertTrue(log.contains("assistant-start attempt=2 result=ok"))
        l.onArrived()
        assertEquals(1, ends)
    }

    @Test
    fun startThrowsTwice_loggedAndFinished() {
        failures = 2
        val l = launcher()
        l.onShow(0)
        assertEquals(2, starts)
        assertEquals(1, ends)
        assertTrue(log.contains("session-finish reason=start-error attempts=2"))
    }

    @Test
    fun overlayMissing_startedAgain_thenGivesUp() {
        val l = launcher()
        l.onShow(0)
        fireTimers()
        assertEquals(2, starts)
        assertTrue(log.contains("assistant-start attempt=1 result=missing after=3000"))
        assertEquals(0, ends)
        fireTimers()
        assertEquals(2, starts)
        assertEquals(1, ends)
        assertTrue(log.contains("session-finish reason=missing attempts=2"))
    }

    @Test
    fun overlayMissingOnce_secondStartArrives() {
        val l = launcher()
        l.onShow(0)
        fireTimers()
        l.onArrived()
        assertEquals(2, starts)
        assertEquals(1, ends)
        assertTrue(timers.isEmpty())
    }

    @Test
    fun hiddenBeforeArrival_finished() {
        val l = launcher()
        l.onShow(0)
        l.onHide()
        assertEquals(1, ends)
        assertTrue(timers.isEmpty())
        assertTrue(log.contains("session-finish reason=hidden attempts=1"))
    }

    @Test
    fun showAgain_restartsTheSequence() {
        val l = launcher()
        l.onShow(0)
        l.onShow(0)
        assertEquals(2, starts)
        assertEquals(1, timers.size)
        l.onArrived()
        assertEquals(1, ends)
    }

    @Test
    fun arrivalsRegistry_callsTheWaitingLauncherOnce() {
        var calls = 0
        val cb: () -> Unit = { calls++ }
        AssistantArrivals.await(cb)
        AssistantArrivals.arrived()
        AssistantArrivals.arrived()
        assertEquals(1, calls)
        AssistantArrivals.await(cb)
        AssistantArrivals.clear(cb)
        AssistantArrivals.arrived()
        assertEquals(1, calls)
    }

    @Test
    fun retryIntentIsMarked() {
        val l = launcher()
        l.onShow(0)
        fireTimers()
        assertEquals(listOf(false, true), retries)
    }

    @Test
    fun destroyedSession_noRetryAndNoSecondEnd() {
        val l = launcher()
        l.onShow(0)
        l.cancel()
        assertTrue(timers.isEmpty())
        assertFalse(l.pending)
        l.onHide()
        l.onArrived()
        assertEquals(1, starts)
        assertEquals(0, ends)
    }

    @Test
    fun retryFilter_lateTwinDoesNotTriggerAgain() {
        // Cold start: the overlay arrives, then the retry intent of the same invocation.
        assertFalse(RetryFilter.triggers(retry = true, sinceArrivalMs = 400))
        // A retry long after the last arrival (first intent lost): it starts the request.
        assertTrue(RetryFilter.triggers(retry = true, sinceArrivalMs = 60_000))
        assertTrue(RetryFilter.triggers(retry = true, sinceArrivalMs = null))
        // A new invocation always triggers.
        assertTrue(RetryFilter.triggers(retry = false, sinceArrivalMs = 100))
    }
}
