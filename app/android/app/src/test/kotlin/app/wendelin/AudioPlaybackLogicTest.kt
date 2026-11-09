package app.wendelin

import org.junit.Test
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull

class AudioPlaybackLogicTest {
    private val speaker = AudioDeviceDesc(2, "Speaker", "", false, true)
    private val headset = AudioDeviceDesc(8, "Buds", "AA:BB:CC:DD:EE:01", false, true)
    private val headsetSco = AudioDeviceDesc(7, "Buds", "AA:BB:CC:DD:EE:01", true, true)
    private fun entry(d: AudioDeviceDesc) = AudioDeviceEntry(AudioDevicePick.keyOf(d), "x", d.product)

    @Test fun noChoiceIsSystem() {
        assertNull(AudioOutputRoute.deviceIndex(null, listOf(speaker, headset)))
    }

    @Test fun chosenDeviceIsFound() {
        assertEquals(1, AudioOutputRoute.deviceIndex(entry(headset), listOf(speaker, headset)))
    }

    @Test fun missingDeviceFallsBackToSystem() {
        assertNull(AudioOutputRoute.deviceIndex(entry(headset), listOf(speaker)))
    }

    @Test fun deviceIsPickedAgainWhenItComesBack() {
        val choice = entry(headset)
        assertNull(AudioOutputRoute.deviceIndex(choice, listOf(speaker)))
        assertEquals(0, AudioOutputRoute.deviceIndex(choice, listOf(headset, speaker)))
    }

    @Test fun inputOnlyDeviceIsNeverAnOutput() {
        val micOnly = AudioDeviceDesc(15, "Mic", "", true, false)
        assertNull(AudioOutputRoute.deviceIndex(entry(micOnly), listOf(micOnly, speaker)))
    }

    @Test fun hiddenScoTwinIsNotPicked() {
        assertNull(AudioOutputRoute.deviceIndex(entry(headsetSco), listOf(headsetSco, headset)))
    }

    @Test fun headBelowTotalKeepsPlaying() {
        val p = PlaybackProgress(1000, 2000, 0)
        assertEquals(PlaybackState.PLAYING, p.onPoll(0, 100))
        assertEquals(PlaybackState.PLAYING, p.onPoll(999, 200))
    }

    @Test fun endIsReportedOnlyWhenTheHeadReachedTheEnd() {
        val p = PlaybackProgress(1000, 2000, 0)
        assertEquals(PlaybackState.PLAYING, p.onPoll(500, 100))
        assertEquals(PlaybackState.DONE, p.onPoll(1000, 200))
    }

    @Test fun noMovementIsStalled() {
        val p = PlaybackProgress(1000, 2000, 0)
        assertEquals(PlaybackState.PLAYING, p.onPoll(0, 1999))
        assertEquals(PlaybackState.STALLED, p.onPoll(0, 2000))
    }

    @Test fun movementResetsTheStallClock() {
        val p = PlaybackProgress(1000, 2000, 0)
        assertEquals(PlaybackState.PLAYING, p.onPoll(100, 1500))
        assertEquals(PlaybackState.PLAYING, p.onPoll(100, 3000))
        assertEquals(PlaybackState.STALLED, p.onPoll(100, 3500))
    }
}
