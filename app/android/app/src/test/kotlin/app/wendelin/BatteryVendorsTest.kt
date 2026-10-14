package app.wendelin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BatteryVendorsTest {
    @Test fun xiaomiFamily() {
        assertEquals("xiaomi", BatteryVendors.vendor("Xiaomi", "Xiaomi"))
        assertEquals("xiaomi", BatteryVendors.vendor("Xiaomi", "POCO"))
        assertEquals("xiaomi", BatteryVendors.vendor("xiaomi", "redmi"))
    }

    @Test fun otherVendors() {
        assertEquals("samsung", BatteryVendors.vendor("samsung", "samsung"))
        assertEquals("oneplus", BatteryVendors.vendor("OnePlus", null))
        assertEquals("huawei", BatteryVendors.vendor("HONOR", "honor"))
    }

    @Test fun stockAndUnknown() {
        assertNull(BatteryVendors.vendor("Google", "google"))
        assertNull(BatteryVendors.vendor(null, null))
        assertTrue(BatteryVendors.pages(null).isEmpty())
        assertTrue(BatteryVendors.pages("xiaomi").isNotEmpty())
    }

    @Test fun bucketNames() {
        assertEquals("active", BatteryVendors.bucketName(10))
        assertEquals("working_set", BatteryVendors.bucketName(20))
        assertEquals("frequent", BatteryVendors.bucketName(30))
        assertEquals("rare", BatteryVendors.bucketName(40))
        assertEquals("restricted", BatteryVendors.bucketName(45))
        assertNull(BatteryVendors.bucketName(null))
    }

    @Test fun visibleVendorPackages() {
        assertTrue("com.miui.securitycenter" in BatteryVendors.packages)
    }
}
