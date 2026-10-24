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

    private var groups = 0
    private var engines = 0
    private val pool = EnginePool<String, Engine>(
        newGroup = { "group${++groups}" },
        onWillDestroy = { e, cb -> e.onDestroy = cb },
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
}
