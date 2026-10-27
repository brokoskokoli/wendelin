package app.wendelin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** WP156: the notification texts come from the app (stored), German „Hey Wendelin“ without. */
class WakeTextsTest {
    private val english = mapOf(
        "listeningTitle" to "Wendelin listens for “Hey Wendelin”",
        "pausedText" to "Until {time}, the microphone is free.",
        "ended" to "Ended ({reason}).",
        "off" to "Off",
    )

    @Test
    fun storedTextsAreUsed() {
        val t = WakeTexts { english[it] }
        assertEquals("Wendelin listens for “Hey Wendelin”", t.listeningTitle)
        assertEquals("Off", t.off)
        assertEquals("Until 07:30, the microphone is free.", t.pausedText("07:30"))
        assertEquals("Ended (no-role).", t.ended("no-role"))
    }

    @Test
    fun withoutStoredTextsGermanHeyWendelinStays() {
        val t = WakeTexts { null }
        assertEquals("Wendelin hört auf „Hey Wendelin“", t.listeningTitle)
        assertEquals("Zeigt, dass Wendelin auf „Hey Wendelin“ hört.", t.channelDesc)
        assertEquals("Bis 07:30 Uhr, das Mikrofon ist frei.", t.pausedText("07:30"))
        assertEquals("Aus", t.off)
        assertTrue(t.ended("x").contains("(x)"))
    }

    @Test
    fun missingOrBlankKeyFallsBackPerKey() {
        val t = WakeTexts { if (it == "off") " " else english[it] }
        assertEquals("Aus", t.off)
        assertEquals("Wendelin listens for “Hey Wendelin”", t.listeningTitle)
    }

    @Test
    fun sanitizeKeepsOnlyKnownShortStrings() {
        val ok = WakeTexts.sanitize(
            mapOf("off" to "Off", "pause" to 5, "resume" to " ", "evil" to "x", "ended" to "y".repeat(401)),
        )
        assertEquals(mapOf("off" to "Off"), ok)
        assertTrue(WakeTexts.sanitize(null).isEmpty())
    }

    @Test
    fun noGermanDefaultNamesPlainWendelinAsWakeWord() {
        for ((k, v) in WakeTexts.DEFAULTS) {
            assertFalse("$k: $v", Regex("„Wendelin“").containsMatchIn(v))
        }
    }
}
