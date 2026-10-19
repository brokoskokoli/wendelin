package app.wendelin

import android.media.AudioManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Which focus gain the answer and the recording request. */
class AudioFocusKindsTest {
    @Test
    fun answerOnlyDucksOtherPlayers() {
        assertEquals(AudioFocusKinds.GAIN_TRANSIENT_MAY_DUCK, AudioFocusKinds.gainFor("duck"))
    }

    @Test
    fun recordingTakesTransientFocus() {
        assertEquals(AudioFocusKinds.GAIN_TRANSIENT, AudioFocusKinds.gainFor("listen"))
    }

    @Test
    fun valuesAreTheAndroidConstants() {
        assertEquals(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT, AudioFocusKinds.GAIN_TRANSIENT)
        assertEquals(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK, AudioFocusKinds.GAIN_TRANSIENT_MAY_DUCK)
    }

    @Test
    fun unknownKindIsNull() {
        assertNull(AudioFocusKinds.gainFor("gain"))
    }

    @Test
    fun lossesPauseAndGainResumes() {
        assertEquals("lost", AudioFocusKinds.stateFor(AudioManager.AUDIOFOCUS_LOSS))
        assertEquals("lost", AudioFocusKinds.stateFor(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT))
        assertEquals("gained", AudioFocusKinds.stateFor(AudioManager.AUDIOFOCUS_GAIN))
    }

    @Test
    fun askedToDuckIsIgnored() {
        assertNull(AudioFocusKinds.stateFor(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK))
        assertNull(AudioFocusKinds.stateFor(99))
    }

    @Test
    fun onlyTheFullLossIsPermanent() {
        assertTrue(AudioFocusKinds.isPermanent(AudioManager.AUDIOFOCUS_LOSS))
        assertFalse(AudioFocusKinds.isPermanent(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT))
    }
}
