package app.wendelin

import org.junit.Assert.assertEquals
import org.junit.Test

class RestrictedSettingsMappingTest {
    @Test fun opModes() {
        assertEquals("allowed", RestrictedSettingsMapping.opMode(0))
        assertEquals("ignored", RestrictedSettingsMapping.opMode(1))
        assertEquals("default", RestrictedSettingsMapping.opMode(3))
    }

    @Test fun otherOrMissingModeIsUnknown() {
        assertEquals("unknown", RestrictedSettingsMapping.opMode(2)) // errored
        assertEquals("unknown", RestrictedSettingsMapping.opMode(99))
        assertEquals("unknown", RestrictedSettingsMapping.opMode(null))
    }

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
