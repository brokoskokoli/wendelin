package app.wendelin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EnginePoolTest {
    private class Engine(val id: Int) {
        var onDestroy: (() -> Unit)? = null
        fun destroy() = onDestroy?.invoke()
    }

    private class Timer(val delayMs: Long, val block: () -> Unit) {
        var cancelled = false
        fun fire() = if (!cancelled) block() else Unit
    }

    private val timers = mutableListOf<Timer>()
    private var groups = 0
    private var engines = 0
    private val pool = EnginePool<String, Engine>(
        newGroup = { "group${++groups}" },
        onWillDestroy = { e, cb -> e.onDestroy = cb },
        destroy = { it.destroy() },
        schedule = { ms, block ->
            val t = Timer(ms, block)
            timers.add(t)
            EnginePool.Cancelable { t.cancelled = true }
        },
    )
    private val spawnedIn = mutableListOf<String>()

    private fun obtain() = pool.obtain { g ->
        spawnedIn.add(g)
        Engine(++engines)
    }

    @Test fun groupIsCreatedOncePerProcessAcrossManyOverlays() {
        repeat(25) { obtain().engine.destroy() }
        assertEquals(1, pool.groupsCreated)
        assertEquals(setOf("group1"), spawnedIn.toSet())
        assertEquals(25, spawnedIn.size)
    }

    @Test fun everyOverlayEngineIsDestroyedAndNoneLeaks() {
        repeat(20) { obtain().engine.destroy() }
        assertEquals(0, pool.live)
    }

    @Test fun firstEngineIsAloneLaterOnesHaveSiblings() {
        val wake = obtain()
        assertTrue(wake.groupIsNew)
        assertFalse(wake.fromSibling)
        val overlay = obtain()
        assertFalse(overlay.groupIsNew)
        assertTrue(overlay.fromSibling)
        assertEquals(1, overlay.siblings)
        assertEquals(2, obtain().siblings)
        assertEquals(3, pool.live)
    }

    @Test fun siblingGoneIsNotCounted() {
        val a = obtain()
        val b = obtain()
        a.engine.destroy()
        assertEquals(1, pool.live)
        assertEquals(1, obtain().siblings)
        b.engine.destroy()
    }

    @Test fun doubleDestroyCountsOnce() {
        val a = obtain()
        obtain()
        a.engine.destroy()
        a.engine.destroy()
        assertEquals(1, pool.live)
    }

    @Test fun failedSpawnLeavesNoGhost() {
        try {
            pool.obtain { error("boom") }
        } catch (e: IllegalStateException) {
            // expected
        }
        assertEquals(0, pool.live)
        assertEquals(0, obtain().siblings)
    }

    // WP145: the overlay activity ends at once, the engine lives on without it.
    @Test fun heldEngineStaysAliveHeadless() {
        val a = obtain().engine
        assertTrue(pool.hold(a, 14_000))
        assertTrue(pool.isHeld(a))
        assertEquals(1, pool.live)
        assertEquals(14_000L, timers.single().delayMs)
    }

    @Test fun heldEngineIsDestroyedWhenDartReports() {
        val a = obtain().engine
        pool.hold(a, 14_000)
        pool.release(a)
        assertEquals(0, pool.live)
        assertFalse(pool.isHeld(a))
        assertTrue("timer stopped", timers.single().cancelled)
    }

    @Test fun heldEngineIsDestroyedByTheTimeout() {
        val a = obtain().engine
        pool.hold(a, 14_000)
        pool.cleanedUp(a)
        timers.single().fire()
        assertEquals(0, pool.live)
        assertEquals(0, pool.holding)
    }

    // The activity is not cleaned up yet: a destroy now would run the detach against a dead engine.
    @Test fun timeoutBeforeCleanUpWaitsForTheDetach() {
        val a = obtain().engine
        pool.hold(a, 14_000)
        timers.single().fire()
        assertEquals("still alive", 1, pool.live)
        assertTrue(pool.isHeld(a))
        pool.cleanedUp(a)
        assertEquals(0, pool.live)
        assertFalse(pool.isHeld(a))
    }

    @Test fun cleanUpWithoutTimeoutKeepsTheEngine() {
        val a = obtain().engine
        pool.hold(a, 14_000)
        pool.cleanedUp(a)
        assertEquals(1, pool.live)
        assertTrue(pool.isHeld(a))
    }

    @Test fun reportAndTimeoutDestroyOnce() {
        var destroyed = 0
        val p = EnginePool<String, Engine>(
            newGroup = { "g" },
            onWillDestroy = { e, cb -> e.onDestroy = cb },
            destroy = { destroyed++; it.destroy() },
            schedule = { ms, block -> timers.add(Timer(ms, block)); EnginePool.Cancelable {} },
        )
        val e = p.obtain { Engine(1) }.engine
        p.hold(e, 1)
        p.release(e)
        timers.last().fire()
        p.release(e)
        assertEquals(1, destroyed)
        assertEquals(0, p.live)
    }

    @Test fun newOverlayWhileHeldGetsANewEngineInTheSameGroup() {
        val old = obtain()
        pool.hold(old.engine, 14_000)
        val fresh = obtain()
        assertTrue(fresh.engine !== old.engine)
        assertTrue("spawned from the living old one", fresh.fromSibling)
        assertEquals(1, pool.groupsCreated)
        assertEquals(2, pool.live)
        pool.release(old.engine)
        assertEquals(1, pool.live)
        assertFalse(pool.isHeld(fresh.engine))
    }

    @Test fun holdTwiceKeepsOneTimer() {
        val a = obtain().engine
        assertTrue(pool.hold(a, 14_000))
        assertFalse(pool.hold(a, 14_000))
        assertEquals(1, timers.size)
    }

    @Test fun releaseOfAnEngineThatIsNotHeldDoesNothing() {
        val a = obtain().engine
        pool.release(a)
        assertEquals(1, pool.live)
    }
}
