package app.wendelin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Fix choice, place name and launch check of the location channel without Android. */
class LocationPickTest {
    private val now = 1_000_000L

    @Test
    fun mostAccurateRecentFixWins() {
        val fixes = listOf(
            FixInfo("network", now - 5_000, 80f),
            FixInfo("gps", now - 30_000, 6f),
            FixInfo("passive", now - 1_000, null),
        )
        assertEquals(1, LocationPick.pick(fixes, now))
    }

    @Test
    fun equalAccuracyTakesNewest() {
        val fixes = listOf(FixInfo("a", now - 20_000, 10f), FixInfo("b", now - 2_000, 10f))
        assertEquals(1, LocationPick.pick(fixes, now))
    }

    @Test
    fun oldAndFutureFixesAreIgnored() {
        val fixes = listOf(
            FixInfo("old", now - LocationPick.MAX_AGE_MS - 1, 1f),
            FixInfo("future", now + 1, 1f),
        )
        assertNull(LocationPick.pick(fixes, now))
        assertEquals(0, LocationPick.pick(listOf(FixInfo("edge", now - LocationPick.MAX_AGE_MS, null)), now))
        assertNull(LocationPick.pick(emptyList(), now))
    }

    @Test
    fun placeNameJoinsDistrictAndTown() {
        assertEquals("Altstadt, Hamburg", LocationPick.placeName("Altstadt", "Hamburg", "HH"))
        assertEquals("Hamburg", LocationPick.placeName(" ", "Hamburg", null))
        assertEquals("Hamburg", LocationPick.placeName("Hamburg", "Hamburg", null))
        assertEquals("Bayern", LocationPick.placeName(null, null, "Bayern"))
        assertNull(LocationPick.placeName(null, "", " "))
    }

    @Test
    fun launchAllowsOnlyMapIntents() {
        assertTrue(LocationPick.isAllowedLaunch("geo", null, null, null))
        assertTrue(LocationPick.isAllowedLaunch("google.navigation", null, null, "com.google.android.apps.maps"))
        assertTrue(LocationPick.isAllowedLaunch("https", "www.google.com", "/maps/dir/", "com.google.android.apps.maps"))
        assertFalse(LocationPick.isAllowedLaunch("https", "evil.example", "/maps/dir/", null))
        assertFalse(LocationPick.isAllowedLaunch("https", "www.google.com", "/search", null))
        assertFalse(LocationPick.isAllowedLaunch("tel", null, null, null))
        assertFalse(LocationPick.isAllowedLaunch("geo", null, null, "com.evil.app"))
        assertFalse(LocationPick.isAllowedLaunch(null, null, null, null))
    }

    @Test
    fun launchAllowsWazeOnlyWithItsLinkAndPackage() {
        assertTrue(LocationPick.isAllowedLaunch("https", "waze.com", "/ul", "com.waze"))
        // Wrong host, other subdomain, wrong path, wrong or missing package, wrong scheme.
        assertFalse(LocationPick.isAllowedLaunch("https", "evil.example", "/ul", "com.waze"))
        assertFalse(LocationPick.isAllowedLaunch("https", "www.waze.com", "/ul", "com.waze"))
        assertFalse(LocationPick.isAllowedLaunch("https", "waze.com", "/live-map", "com.waze"))
        assertFalse(LocationPick.isAllowedLaunch("https", "waze.com", null, "com.waze"))
        assertFalse(LocationPick.isAllowedLaunch("https", "waze.com", "/ul", "com.google.android.apps.maps"))
        assertFalse(LocationPick.isAllowedLaunch("https", "waze.com", "/ul", "com.evil.app"))
        assertFalse(LocationPick.isAllowedLaunch("https", "waze.com", "/ul", null))
        assertFalse(LocationPick.isAllowedLaunch("http", "waze.com", "/ul", "com.waze"))
        assertFalse(LocationPick.isAllowedLaunch("waze", "waze.com", "/ul", "com.waze"))
        // The Waze package may not carry Google Maps links or map schemes.
        assertFalse(LocationPick.isAllowedLaunch("https", "www.google.com", "/maps/dir/", "com.waze"))
        assertFalse(LocationPick.isAllowedLaunch("geo", null, null, "com.waze"))
    }
}
