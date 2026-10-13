package app.wendelin

import android.content.pm.PackageManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Redirect and request checks of the OAuth login, and the recognizer service switch. */
class OAuthRedirectTest {
    private val expected = OAuthRedirect.Target("app.wendelin", "oauth", "/mcp")

    @Test
    fun requestNeedsHttpAddressRedirectAndState() {
        assertTrue(OAuthRedirect.isValidRequest("https", true, "abc"))
        assertTrue(OAuthRedirect.isValidRequest("http", true, "abc"))
        assertFalse(OAuthRedirect.isValidRequest("javascript", true, "abc"))
        assertFalse(OAuthRedirect.isValidRequest("file", true, "abc"))
        assertFalse(OAuthRedirect.isValidRequest(null, true, "abc"))
        assertFalse(OAuthRedirect.isValidRequest("https", false, "abc"))
        assertFalse(OAuthRedirect.isValidRequest("https", true, ""))
        assertFalse(OAuthRedirect.isValidRequest("https", true, null))
    }

    @Test
    fun redirectNeedsTheStateOfTheRunningLogin() {
        assertTrue(OAuthRedirect.accepts(expected, expected, "s1", "s1"))
        assertFalse(OAuthRedirect.accepts(expected, expected, "s1", "other"))
        assertFalse(OAuthRedirect.accepts(expected, expected, "s1", null))
    }

    @Test
    fun redirectNeedsSchemeHostAndPath() {
        assertFalse(OAuthRedirect.accepts(expected, expected.copy(scheme = "https"), "s", "s"))
        assertFalse(OAuthRedirect.accepts(expected, expected.copy(host = "evil"), "s", "s"))
        assertFalse(OAuthRedirect.accepts(expected, expected.copy(path = "/other"), "s", "s"))
    }

    @Test
    fun recognizerServiceIsEnabledOnlyWithRoleAndOffer() {
        val on = PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        val off = PackageManager.COMPONENT_ENABLED_STATE_DEFAULT
        assertEquals(on, RecognizerSwitch.wantedState(holdsRole = true, offered = true))
        assertEquals(off, RecognizerSwitch.wantedState(holdsRole = true, offered = false))
        assertEquals(off, RecognizerSwitch.wantedState(holdsRole = false, offered = true))
        assertEquals(off, RecognizerSwitch.wantedState(holdsRole = false, offered = false))
    }

    @Test
    fun recognizerConfigKeepsDefaultsForInvalidArguments() {
        val d = RecognizerConfig()
        assertEquals(d, RecognizerConfig.fromArgs(null))
        assertEquals(d, RecognizerConfig.fromArgs(mapOf("model" to "gpt", "language" to "xx", "vadThreshold" to 1.5, "minSpeechMs" to 5)))
        val ok = RecognizerConfig.fromArgs(
            mapOf("model" to "whisper-tiny", "language" to "de", "vadThreshold" to 0.3, "minSpeechMs" to 300),
        )
        assertEquals(RecognizerConfig("whisper-tiny", "de", 0.3, 300), ok)
        assertEquals("", RecognizerConfig.fromArgs(mapOf("language" to "")).language)
    }
}
