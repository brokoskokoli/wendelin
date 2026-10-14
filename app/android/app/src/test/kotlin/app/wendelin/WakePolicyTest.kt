package app.wendelin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Start/stop logic of the wake-word service without Android (WP50). */
class WakePolicyTest {
    private val on = WakeSettings(enabled = true)
    private val now = 1_000_000L

    private fun decide(
        s: WakeSettings = on,
        role: Boolean = true,
        mic: Boolean = true,
        charging: Boolean = true,
    ) = WakePolicy.decide(s, role, mic, charging, now)

    @Test
    fun startsWhenEverythingFits() {
        assertEquals(WakeDecision.Start, decide())
    }

    @Test
    fun theReasonsComeInAFixedOrder() {
        assertEquals(WakeDecision.Skip("disabled"), decide(WakeSettings(), role = false, mic = false))
        assertEquals(WakeDecision.Skip("no-role"), decide(role = false, mic = false))
        assertEquals(WakeDecision.Skip("no-permission"), decide(mic = false))
        assertEquals(
            WakeDecision.Skip("paused"),
            decide(on.copy(pausedUntilMs = now + 1, mode = WakeMode.CHARGING), charging = false),
        )
        assertEquals(WakeDecision.Skip("not-charging"), decide(charging = false))
    }

    @Test
    fun callAndForeignRecordingCloseTheMicrophoneInTheService() {
        assertTrue(WakePolicy.closesMicFor("call"))
        assertTrue(WakePolicy.closesMicFor("recording"))
        assertFalse(WakePolicy.closesMicFor(null))
    }

    @Test
    fun alwaysModeIgnoresCharging() {
        assertEquals(WakeDecision.Start, decide(on.copy(mode = WakeMode.ALWAYS), charging = false))
    }

    @Test
    fun aPauseEndsAtItsTime() {
        assertEquals(WakeDecision.Start, decide(on.copy(pausedUntilMs = now)))
        assertEquals(WakeDecision.Start, decide(on.copy(pausedUntilMs = now - 5)))
    }

    @Test
    fun unpluggingStopsOnlyTheChargingMode() {
        assertTrue(WakePolicy.stopsOnUnplug(WakeMode.CHARGING, charging = false))
        assertFalse(WakePolicy.stopsOnUnplug(WakeMode.CHARGING, charging = true))
        assertFalse(WakePolicy.stopsOnUnplug(WakeMode.ALWAYS, charging = false))
    }

    @Test
    fun callsAndForeignRecordingsNeedTheMicrophone() {
        assertEquals("call", WakePolicy.conflict(audioMode = 2, foreignRecording = false))
        assertEquals("call", WakePolicy.conflict(audioMode = 3, foreignRecording = true))
        assertEquals("call", WakePolicy.conflict(audioMode = 4, foreignRecording = false))
        assertEquals("recording", WakePolicy.conflict(audioMode = 0, foreignRecording = true))
        assertNull(WakePolicy.conflict(audioMode = 0, foreignRecording = false))
        assertNull(WakePolicy.conflict(audioMode = 1, foreignRecording = false))
    }

    @Test
    fun theDefaultModeIsChargingAndUnknownValuesFallBack() {
        assertEquals(WakeMode.CHARGING, WakeSettings().mode)
        assertEquals(WakeMode.ALWAYS, WakeMode.parse("always"))
        assertEquals(WakeMode.CHARGING, WakeMode.parse("nonsense"))
        assertEquals(WakeMode.CHARGING, WakeMode.parse(null))
    }

    @Test
    fun channelArgumentsChangeOnlyWhatTheyName() {
        val old = WakeSettings(enabled = true, mode = WakeMode.ALWAYS, verify = true, pausedUntilMs = 5)
        assertEquals(old, old.withArgs(null))
        assertEquals(old.copy(verify = false), old.withArgs(mapOf("verify" to false)))
        assertEquals(old.copy(mode = WakeMode.CHARGING), old.withArgs(mapOf("mode" to "charging")))
        // Wrong types keep the old values.
        assertEquals(old, old.withArgs(mapOf("enabled" to "yes", "mode" to 3, "verify" to 1)))
        // Switching off also ends a pause.
        assertEquals(WakeSettings(enabled = false, mode = WakeMode.ALWAYS), old.withArgs(mapOf("enabled" to false)))
    }

    @Test
    fun aHitIsHandedOverOnceAndGoesStale() {
        WakeHandoff.clear()
        val pcm = byteArrayOf(1, 2, 3, 4)
        WakeHandoff.put(pcm, 100)
        assertTrue(WakeHandoff.pending())
        assertEquals(pcm, WakeHandoff.take(200))
        assertFalse(WakeHandoff.pending())
        assertNull(WakeHandoff.take(300))
        WakeHandoff.put(pcm, 100)
        assertNull(WakeHandoff.take(100 + WakeHandoff.MAX_AGE_MS + 1))
    }
}
