package app.wendelin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Evaluation of `voice_recognition_service` (B12): component comparison without Android. */
class RecognitionServiceStatusTest {
    private val pkg = "app.wendelin"
    private val cls = "app.wendelin.WendelinRecognitionService"

    private fun state(value: String?) = RecognitionServiceStatus.evaluate(value, pkg, cls)

    @Test
    fun ownServiceShortAndLongFormIsActive() {
        assertEquals("active", state("app.wendelin/.WendelinRecognitionService").state)
        assertEquals("active", state("app.wendelin/app.wendelin.WendelinRecognitionService").state)
        assertEquals("active", state(" app.wendelin/.WendelinRecognitionService\n").state)
    }

    @Test
    fun otherServiceNamesItsPackage() {
        val google = state(
            "com.google.android.tts/com.google.android.apps.speech.tts.googletts.service." +
                "GoogleTTSRecognitionService",
        )
        assertEquals("other", google.state)
        assertEquals("com.google.android.tts", google.otherPackage)
    }

    @Test
    fun otherClassOfOwnPackageIsNotActive() {
        val sameApp = state("app.wendelin/.WendelinVoiceInteractionService")
        assertEquals("other", sameApp.state)
        assertEquals("app.wendelin", sameApp.otherPackage)
        // Same class name in another package (e.g. a debug build with a suffix).
        assertEquals("other", state("app.wendelin.debug/app.wendelin.WendelinRecognitionService").state)
    }

    @Test
    fun emptyOrBrokenValueIsUnknown() {
        for (value in listOf(null, "", "   ", "app.wendelin", "/.Cls", "app.wendelin/", "a/b/c")) {
            val e = state(value)
            assertEquals("value: $value", "unknown", e.state)
            assertNull(e.otherPackage)
        }
    }

    @Test
    fun channelAnswerCarriesTheNameOnlyForOther() {
        assertEquals(
            mapOf("state" to "other", "appName" to "Speech Services by Google"),
            RecognitionServiceStatus.toArgs(
                RecognitionServiceStatus.Evaluation("other", "com.google.android.tts"),
                "Speech Services by Google",
            ),
        )
        assertEquals(
            mapOf("state" to "active"),
            RecognitionServiceStatus.toArgs(RecognitionServiceStatus.Evaluation("active"), "x"),
        )
        assertEquals(
            mapOf("state" to "unknown"),
            RecognitionServiceStatus.toArgs(RecognitionServiceStatus.Evaluation("unknown"), null),
        )
    }
}
