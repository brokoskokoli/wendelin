package app.wendelin

/**
 * The names this phone may show in Spotify Connect (WP161): the name the user gave it
 * (`Settings.Global.device_name`), the market name (`ro.product.marketname`) and the model.
 * Spotify takes the name from the OS, which differs by vendor, so several are offered and the
 * Dart side compares them without case. Blank and duplicate entries are dropped.
 */
object HostDeviceNames {
    fun pick(deviceName: String?, marketName: String?, model: String?): List<String> =
        listOf(deviceName, marketName, model)
            .mapNotNull { it?.trim() }
            .filter { it.isNotEmpty() }
            .distinctBy { it.lowercase() }
}
