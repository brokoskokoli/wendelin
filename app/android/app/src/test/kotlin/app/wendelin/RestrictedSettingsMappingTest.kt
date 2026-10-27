package app.wendelin

import org.junit.Assert.assertEquals
import org.junit.Test

class RestrictedSettingsMappingTest {
    @Test fun fileSources() {
        assertEquals("file", RestrictedSettingsMapping.installSource(35, 3))
        assertEquals("file", RestrictedSettingsMapping.installSource(35, 4))
    }

    @Test fun otherSourcesAreSession() {
        for (s in listOf(0, 1, 2)) {
            assertEquals("session", RestrictedSettingsMapping.installSource(35, s))
        }
    }

    @Test fun belowApi33OrUnreadableIsUnknown() {
        assertEquals("unknown", RestrictedSettingsMapping.installSource(32, 4))
        assertEquals("unknown", RestrictedSettingsMapping.installSource(35, null))
    }
}
