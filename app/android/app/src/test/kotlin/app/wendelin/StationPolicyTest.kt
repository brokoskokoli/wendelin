package app.wendelin

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StationPolicyTest {
    @After
    fun reset() {
        StationState.active = false
        ChatState.visible = false
    }

    @Test
    fun onlyTheEndButtonAfterUnlockingEndsTheStation() {
        assertTrue(StationPolicy.endsOn(StationEvent.END_UNLOCKED))
        // Unplugging, back, home, the screen going off and any voice command leave it running.
        for (event in listOf(
            StationEvent.UNPLUG,
            StationEvent.BACK,
            StationEvent.HOME,
            StationEvent.SCREEN_OFF,
            StationEvent.VOICE,
        )) {
            assertFalse("$event must not end the station", StationPolicy.endsOn(event))
        }
    }

    @Test
    fun theActivityClosesOnlyOnAnUnlockedDevice() {
        assertFalse(StationPolicy.mayFinish(locked = true))
        assertTrue(StationPolicy.mayFinish(locked = false))
    }

    @Test
    fun finishFromDartIsRefusedForTheLockedStationButNotTheOverlay() {
        var closed = 0
        assertFalse(StationPolicy.finishIfAllowed(isStation = true, locked = true) { closed++ })
        assertEquals(0, closed)
        assertTrue(StationPolicy.finishIfAllowed(isStation = true, locked = false) { closed++ })
        assertEquals(1, closed)
        // The overlay over the lock screen closes as before.
        assertTrue(StationPolicy.finishIfAllowed(isStation = false, locked = true) { closed++ })
        assertEquals(2, closed)
    }

    @Test
    fun theVoiceCommandStartsOnlyUnlocked() {
        assertFalse(StationPolicy.voiceStartAllowed(locked = true))
        assertTrue(StationPolicy.voiceStartAllowed(locked = false))
    }

    @Test
    fun theTileAsksToUnlockFirst() {
        assertTrue(StationPolicy.tileNeedsUnlock(locked = true))
        assertFalse(StationPolicy.tileNeedsUnlock(locked = false))
    }

    @Test
    fun brightnessGrowsWithTheLightAndStaysInRange() {
        assertEquals(StationPolicy.MIN_BRIGHTNESS, StationPolicy.brightnessFor(0f), 0f)
        assertEquals(StationPolicy.MAX_BRIGHTNESS, StationPolicy.brightnessFor(20000f), 0f)
        assertTrue(StationPolicy.brightnessFor(50f) < StationPolicy.brightnessFor(300f))
        assertTrue(StationPolicy.brightnessFor(2f) >= StationPolicy.MIN_BRIGHTNESS)
        assertTrue(StationPolicy.QUIET_BRIGHTNESS < StationPolicy.MIN_BRIGHTNESS)
    }

    @Test
    fun aDarkRoomIsBelowAboutFifteenLux() {
        assertTrue(StationPolicy.isDark(3f))
        assertFalse(StationPolicy.isDark(200f))
    }

    @Test
    fun theStationIsNeverReportedAsTheVisibleChat() {
        StationState.active = true
        ChatState.report(true)
        assertFalse(ChatState.visible)
        StationState.active = false
        ChatState.report(true)
        assertTrue(ChatState.visible)
    }

    @Test
    fun aWakeWordHitDuringTheStationOpensTheOverlay() {
        // Even if a stale flag says the chat is visible (until WP100).
        assertEquals(
            HitRoute.OVERLAY,
            WakePolicy.routeHit(
                chatVisible = true,
                locked = false,
                hostAvailable = true,
                stationActive = true,
            ),
        )
        assertEquals(
            HitRoute.CHAT,
            WakePolicy.routeHit(chatVisible = true, locked = false, hostAvailable = true),
        )
    }
}
