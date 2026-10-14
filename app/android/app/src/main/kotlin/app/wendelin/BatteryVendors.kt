package app.wendelin

/**
 * Manufacturer-specific power management (WP56): which vendor a device belongs to and which
 * settings pages may be reachable by intent. Android-free so a JVM test can check it. The
 * values of those pages cannot be read, so Dart only shows a checklist for the vendor.
 */
object BatteryVendors {
    /** A settings page as explicit component (package, class). */
    data class Page(val pkg: String, val cls: String)

    private val xiaomi = listOf(
        Page("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"),
        Page("com.miui.powerkeeper", "com.miui.powerkeeper.ui.HiddenAppsConfigActivity"),
    )

    private val pages: Map<String, List<Page>> = mapOf(
        "xiaomi" to xiaomi,
        "samsung" to listOf(
            Page("com.samsung.android.lool", "com.samsung.android.sm.battery.ui.BatteryActivity"),
        ),
        "oneplus" to listOf(
            Page("com.oneplus.security", "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"),
        ),
        "huawei" to listOf(
            Page("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
        ),
    )

    /** Packages whose settings pages must be visible (manifest `<queries>`). */
    val packages: Set<String> = pages.values.flatten().map { it.pkg }.toSet()

    /**
     * Vendor id for [manufacturer] / [brand] (`Build.MANUFACTURER`, `Build.BRAND`), or `null`
     * for stock Android and unknown vendors. Xiaomi covers Redmi and POCO (HyperOS, MIUI).
     */
    fun vendor(manufacturer: String?, brand: String? = null): String? {
        val m = "${manufacturer.orEmpty()} ${brand.orEmpty()}".lowercase()
        return when {
            "xiaomi" in m || "redmi" in m || "poco" in m -> "xiaomi"
            "samsung" in m -> "samsung"
            "oneplus" in m -> "oneplus"
            "huawei" in m || "honor" in m -> "huawei"
            else -> null
        }
    }

    /** Candidate pages of [vendor], most specific first. */
    fun pages(vendor: String?): List<Page> = pages[vendor].orEmpty()

    /** App standby bucket (UsageStatsManager constants) as a name; `null` if unknown. */
    fun bucketName(bucket: Int?): String? = when {
        bucket == null -> null
        bucket <= 10 -> "active"
        bucket <= 20 -> "working_set"
        bucket <= 30 -> "frequent"
        bucket <= 40 -> "rare"
        bucket <= 45 -> "restricted"
        else -> "never"
    }
}
