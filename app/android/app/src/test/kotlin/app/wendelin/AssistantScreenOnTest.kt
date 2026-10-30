package app.wendelin

import android.view.WindowManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Tests for [AssistantScreenOn] managing WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON (WP186, K148).
 */
class AssistantScreenOnTest {
    private val addedFlags = mutableListOf<Int>()
    private val clearedFlags = mutableListOf<Int>()

    private fun screenOn() = AssistantScreenOn(
        addFlags = { addedFlags.add(it) },
        clearFlags = { clearedFlags.add(it) },
    )

    @Test
    fun flagConstantMatchesAndroidFlag() {
        assertEquals(128, WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    @Test
    fun acquireSetsFlagKeepScreenOn() {
        val s = screenOn()
        assertFalse(s.screenOnHeld)

        s.acquire()

        assertTrue(s.screenOnHeld)
        assertEquals(listOf(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON), addedFlags)
        assertTrue(clearedFlags.isEmpty())
    }

    @Test
    fun releaseClearsFlagKeepScreenOn() {
        val s = screenOn()
        s.acquire()
        s.release()

        assertFalse(s.screenOnHeld)
        assertEquals(listOf(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON), clearedFlags)
    }

    @Test
    fun repeatedAcquireIsIdempotent() {
        val s = screenOn()
        s.acquire()
        s.acquire()

        assertTrue(s.screenOnHeld)
        assertEquals(1, addedFlags.size)
        assertEquals(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON, addedFlags.single())
    }

    @Test
    fun repeatedReleaseIsIdempotent() {
        val s = screenOn()
        s.acquire()
        // Overlay close flow: closeOverlay() -> releaseHost() -> onDestroy()
        s.release()
        s.release()
        s.release()

        assertFalse(s.screenOnHeld)
        assertEquals(1, clearedFlags.size)
        assertEquals(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON, clearedFlags.single())
    }

    @Test
    fun releaseBeforeAcquireDoesNothing() {
        val s = screenOn()
        s.release()

        assertFalse(s.screenOnHeld)
        assertTrue(addedFlags.isEmpty())
        assertTrue(clearedFlags.isEmpty())
    }

    @Test
    fun reacquireAfterReleaseWorks() {
        val s = screenOn()
        s.acquire()
        s.release()
        s.acquire()

        assertTrue(s.screenOnHeld)
        assertEquals(2, addedFlags.size)
        assertEquals(1, clearedFlags.size)
    }
}
