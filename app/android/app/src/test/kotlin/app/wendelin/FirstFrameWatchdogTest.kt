package app.wendelin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FirstFrameWatchdogTest {
    private val log = mutableListOf<String>()
    private val timers = mutableListOf<Pair<Long, () -> Unit>>()
    private var finished = 0

    private fun watchdog() = FirstFrameWatchdog(
        schedule = { delay, block ->
            val entry = delay to block
            timers.add(entry)
            AssistantLauncher.Cancelable { timers.remove(entry) }
        },
        finish = { finished++ },
        log = { log.add(it) },
    )

    @Test fun noFrameFinishesAndLogs() {
        watchdog().start()
        assertEquals(10_000L, timers.single().first)
        timers.single().second()
        assertEquals(1, finished)
        assertEquals(listOf("overlay-first-frame-timeout after=10000"), log)
    }

    @Test fun frameInTimeCancels() {
        val w = watchdog()
        w.start()
        w.stop()
        assertTrue(timers.isEmpty())
        assertEquals(0, finished)
    }

    @Test fun lateFireAfterStopDoesNothing() {
        val w = watchdog()
        w.start()
        val block = timers.single().second
        w.stop()
        block()
        assertEquals(0, finished)
        assertTrue(log.isEmpty())
    }
}
