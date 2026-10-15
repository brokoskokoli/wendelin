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
    fun offByUserIsClearedByEveryConfigure() {
        val off = WakeSettings(enabled = false, offByUser = true)
        assertTrue(off.withArgs(null).offByUser)
        assertTrue(off.withArgs(mapOf("verify" to false)).offByUser)
        val on = off.withArgs(mapOf("enabled" to true))
        assertTrue(on.enabled)
        assertFalse(on.offByUser)
        assertFalse(off.withArgs(mapOf("enabled" to false)).offByUser)
    }

    @Test
    fun startMicWaitsWhileAConflictHolds() {
        assertFalse(WakePolicy.mayStartMic("call"))
        assertFalse(WakePolicy.mayStartMic("recording"))
        assertTrue(WakePolicy.mayStartMic(null))
    }

    @Test
    fun aHitIsHandedOverOnceAndGoesStale() {
        WakeHandoff.clear()
        val pcm = byteArrayOf(1, 2, 3, 4)
        WakeHandoff.put(pcm, 100)
        assertTrue(WakeHandoff.pending())
        assertEquals(pcm.toList(), WakeHandoff.take(200)!!.pcm.toList())
        assertFalse(WakeHandoff.pending())
        assertNull(WakeHandoff.take(300))
        WakeHandoff.put(pcm, 100)
        assertNull(WakeHandoff.take(100 + WakeHandoff.MAX_AGE_MS + 1))
    }

    @Test
    fun theCaptureIsAttachedWithoutGapOrOverlap() {
        WakeHandoff.clear()
        val tap = WakeMicTap()
        // Chunks 0..9 of 480 samples go to Dart (sample value = running index); Dart confirms the
        // hit at position 7 * 480 and its pre-roll ends there; chunks 7..9 were already on the way.
        fun chunk(i: Int) = ByteArray(960) { n -> if (n % 2 == 0) (i * 10).toByte() else 0 }
        for (i in 0 until 10) tap.onChunk(chunk(i))
        val pre = chunk(99)
        WakeHandoff.put(pre, 100, 400)
        WakeHandoff.beginCapture(tap.tailAfter(7L * 480))
        assertTrue(WakeHandoff.capturing())
        WakeHandoff.append(chunk(10))
        WakeHandoff.append(chunk(11))
        val taken = WakeHandoff.take(200)!!
        assertFalse(WakeHandoff.capturing())
        assertEquals(400, taken.wakeEnd)
        // pre-roll + chunks 7..11, each exactly once and in order
        assertEquals(960 * 6, taken.pcm.size)
        val order = (1 until 6).map { taken.pcm[it * 960].toInt() }
        assertEquals(listOf(70, 80, 90, 100, 110), order)
        assertEquals(5 * 480 * 1000L / 16_000, taken.capturedMs)
        // after the take nothing is collected any more
        WakeHandoff.append(chunk(12))
        assertNull(WakeHandoff.take(300))
    }

    @Test
    fun aStaleCaptureFlagDoesNotMakeTheWakeWordDeaf() {
        // Service ended during a handover: release() clears the hit, the flag is gone.
        WakeHandoff.clear()
        WakeHandoff.put(ByteArray(2), 0)
        WakeHandoff.beginCapture(ByteArray(0))
        assertTrue(WakePolicy.ignoresMicCalls(WakeHandoff.capturing(), micOpen = true))
        WakeHandoff.clear()
        assertFalse(WakeHandoff.capturing())
        assertFalse(WakePolicy.ignoresMicCalls(WakeHandoff.capturing(), micOpen = true))
        // A flag without an open microphone does not block the restart either.
        assertFalse(WakePolicy.ignoresMicCalls(capturing = true, micOpen = false))
    }

    @Test
    fun theTimeOfTheLastCollectedChunkIsHandedOver() {
        WakeHandoff.clear()
        WakeHandoff.put(ByteArray(2), 0)
        WakeHandoff.beginCapture(ByteArray(0))
        WakeHandoff.append(ByteArray(960), 1000)
        WakeHandoff.append(ByteArray(960), 1060)
        assertEquals(1060, WakeHandoff.take(1).let { it!!.lastSampleAtMs })
        WakeHandoff.put(ByteArray(2), 0)
        assertEquals(0, WakeHandoff.take(1)!!.lastSampleAtMs)
    }

    @Test
    fun captureStopsAtTheLimit() {
        WakeHandoff.clear()
        WakeHandoff.put(ByteArray(2), 0)
        WakeHandoff.beginCapture(ByteArray(0))
        repeat(20) { WakeHandoff.append(ByteArray(WakeHandoff.MAX_CAPTURE_BYTES / 10)) }
        assertEquals(2 + WakeHandoff.MAX_CAPTURE_BYTES, WakeHandoff.take(1)!!.pcm.size)
    }

    @Test
    fun theTapKeepsOnlyTheRecentChunks() {
        val tap = WakeMicTap(keepBytes = 2000)
        repeat(10) { tap.onChunk(ByteArray(960)) }
        assertEquals(4800L, tap.sent)
        assertEquals(0, tap.tailAfter(4800).size)
        assertEquals(960, tap.tailAfter(4320).size)
        // older than kept: only what is still there
        assertTrue(tap.tailAfter(0).size <= 3 * 960)
    }
}
