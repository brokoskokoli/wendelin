package app.wendelin

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UnlockGuardTest {
    private var time = 10_000L
    private val guard = UnlockGuard { time }

    @Test
    fun inactiveBeforeAnyRequest() {
        assertFalse(guard.active())
    }

    @Test
    fun activeWhileRequestIsOpen() {
        guard.begin()
        time += 60_000
        assertTrue(guard.active())
    }

    @Test
    fun staysActiveForGraceAfterSuccess() {
        guard.begin()
        guard.end()
        time += UnlockGuard.GRACE_MS - 1
        assertTrue("onStop right after the keyguard result is not leaving", guard.active())
    }

    @Test
    fun endsAfterGrace() {
        guard.begin()
        guard.end()
        time += UnlockGuard.GRACE_MS
        assertFalse("a later stop (home) closes the overlay again", guard.active())
    }

    @Test
    fun newRequestRestartsGuard() {
        guard.begin()
        guard.end()
        time += UnlockGuard.GRACE_MS + 1
        guard.begin()
        assertTrue(guard.active())
    }
}
