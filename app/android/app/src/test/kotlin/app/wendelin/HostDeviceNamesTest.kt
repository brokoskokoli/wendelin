package app.wendelin

import org.junit.Assert.assertEquals
import org.junit.Test

class HostDeviceNamesTest {
    @Test fun allSourcesInOrder() {
        assertEquals(listOf("Mein Handy", "Pixel 8", "G9BQD"), HostDeviceNames.pick("Mein Handy", "Pixel 8", "G9BQD"))
    }

    @Test fun blankMissingAndDuplicatesDropped() {
        assertEquals(listOf("Pixel 8"), HostDeviceNames.pick(null, " Pixel 8 ", "pixel 8"))
        assertEquals(emptyList<String>(), HostDeviceNames.pick("", "  ", null))
    }
}
