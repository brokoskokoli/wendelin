package app.wendelin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Test

/** Session choice, position and names of the media channel without Android. */
class MediaSessionPickTest {
    private fun s(state: Int) = SessionInfo("p$state", state)

    @Test
    fun playingBeatsPausedAndOrder() {
        val list = listOf(s(MediaSessionPick.STATE_PAUSED), s(MediaSessionPick.STATE_PLAYING))
        assertEquals(1, MediaSessionPick.pick(list))
    }

    @Test
    fun connectingCountsAsPlaying() {
        assertTrue(MediaSessionPick.isPlaying(MediaSessionPick.STATE_CONNECTING))
        assertFalse(MediaSessionPick.isPlaying(MediaSessionPick.STATE_STOPPED))
    }

    @Test
    fun positionDoesNotAdvanceWithoutUpdateTime() {
        assertEquals(10_000L, MediaSessionPick.position(10_000, 0, 3_000, 1f, true, 0))
        assertEquals(10_000L, MediaSessionPick.position(10_000, 3_000, 3_000, 1f, true, 0))
    }

    @Test
    fun bufferingCountsAsPlaying() {
        assertTrue(MediaSessionPick.isPlaying(MediaSessionPick.STATE_BUFFERING))
        assertFalse(MediaSessionPick.isPlaying(MediaSessionPick.STATE_PAUSED))
    }

    @Test
    fun firstPausedWhenNothingPlays() {
        val list = listOf(s(MediaSessionPick.STATE_STOPPED), s(MediaSessionPick.STATE_PAUSED), s(MediaSessionPick.STATE_PAUSED))
        assertEquals(1, MediaSessionPick.pick(list))
    }

    @Test
    fun stoppedAndEmptyAreNotUsable() {
        assertNull(MediaSessionPick.pick(emptyList()))
        assertNull(MediaSessionPick.pick(listOf(s(MediaSessionPick.STATE_NONE), s(MediaSessionPick.STATE_STOPPED))))
    }

    @Test
    fun otherStatesAreTheLastResort() {
        assertEquals(0, MediaSessionPick.pick(listOf(s(4))))
    }

    @Test
    fun positionAdvancesWhilePlayingWithSpeed() {
        assertEquals(
            10_000L + 4_000L,
            MediaSessionPick.position(10_000, 1_000, 3_000, 2f, true, 0),
        )
    }

    @Test
    fun positionStandsStillWhenPausedAndClampsToDuration() {
        assertEquals(10_000L, MediaSessionPick.position(10_000, 1_000, 99_000, 1f, false, 60_000))
        assertEquals(60_000L, MediaSessionPick.position(59_000, 1_000, 9_000, 1f, true, 60_000))
    }

    @Test
    fun unknownPositionIsNull() {
        assertNull(MediaSessionPick.position(MediaSessionPick.POSITION_UNKNOWN, 0, 5, 1f, true, 0))
    }

    @Test
    fun durationZeroOrNegativeIsUnknown() {
        assertNull(MediaSessionPick.duration(0))
        assertNull(MediaSessionPick.duration(-1))
        assertEquals(5L, MediaSessionPick.duration(5))
    }

    @Test
    fun appNamePrefersSystemLabel() {
        assertEquals("Mein Player", MediaSessionPick.appName("x.y", "Mein Player"))
        assertEquals("Audible", MediaSessionPick.appName("com.audible.application", null))
        assertEquals("Audible", MediaSessionPick.appName("com.audible.application", " "))
        assertEquals("x.y", MediaSessionPick.appName("x.y", null))
    }
}
