package app.wendelin

import java.security.MessageDigest

/**
 * What [AudioDevicePick] needs of an `AudioDeviceInfo`, without Android types (testable on the JVM).
 * [address] is private to the device: it only goes into the hash of [AudioDevicePick.keyOf], never
 * into a log line or to Dart.
 */
data class AudioDeviceDesc(
    val type: Int,
    val product: String,
    val address: String,
    val isSource: Boolean,
    val isSink: Boolean,
)

/** One entry of the device list as Dart sees it: the stable [key], a [type] name and the product name. */
data class AudioDeviceEntry(val key: String, val type: String, val name: String)

/**
 * Stable device keys and the choice "selected device, else system" (WP188, K149).
 *
 * `AudioDeviceInfo.id` changes with every reconnect, so the key is made of type, product name and a
 * hash of the address. The hash keeps the address out of the key itself: even a key that lands in
 * a log reveals no MAC address. The key is opaque for the UI (shown: product name and type only).
 */
object AudioDevicePick {
    const val INPUT = "input"
    const val OUTPUT = "output"

    // android.media.AudioDeviceInfo.TYPE_* as numbers (the newer ones need a higher API level).
    private val SOURCE_TYPES = mapOf(
        15 to "builtin_mic",
        3 to "wired_headset",
        5 to "line",
        7 to "bluetooth_sco",
        11 to "usb",
        22 to "usb",
        26 to "bluetooth_le",
    )
    private val SINK_TYPES = mapOf(
        2 to "builtin_speaker",
        1 to "earpiece",
        3 to "wired_headset",
        4 to "wired_headset",
        5 to "line",
        6 to "line",
        7 to "bluetooth_sco",
        8 to "bluetooth_a2dp",
        11 to "usb",
        22 to "usb",
        23 to "hearing_aid",
        26 to "bluetooth_le",
        27 to "bluetooth_le",
    )

    /** `true` for a known direction name. */
    fun isDirection(direction: String) = direction == INPUT || direction == OUTPUT

    /** The type name of [d] for [direction]; `null` if the device is no choice (HDMI, telephony, ...). */
    fun typeName(d: AudioDeviceDesc, direction: String): String? = when (direction) {
        INPUT -> if (d.isSource) SOURCE_TYPES[d.type] else null
        OUTPUT -> if (d.isSink) SINK_TYPES[d.type] else null
        else -> null
    }

    private val BLUETOOTH_TYPES = setOf(7, 8, 23, 26, 27)
    private const val SCO_SINK = 7
    private val USB_TYPES = setOf(11, 22)

    /** Whether [d] is a Bluetooth output (A2DP, LE or SCO). */
    fun isBluetoothSink(d: AudioDeviceDesc): Boolean = d.isSink && d.type in BLUETOOTH_TYPES

    /**
     * The stable key: `type|product|hash`. The type is the raw Android type (not the shared name)
     * so a wired headset and headphones stay apart.
     *
     * The hash covers only the part of the address that stays the same: Bluetooth on Android 12+
     * returns an anonymised address (`XX:XX:XX:XX:A1:B2`) without BLUETOOTH_CONNECT and the real
     * one with it, so only the last 5 characters (upper case) count. A USB address
     * (`card=N;device=M`) changes with every re-plug and is left out: two identical USB devices
     * are therefore one entry. Everything else hashes the whole address.
     */
    fun keyOf(d: AudioDeviceDesc): String =
        "${d.type}|${d.product.replace('|', ' ').trim()}|${hash(stableAddress(d))}"

    private fun stableAddress(d: AudioDeviceDesc): String = when (d.type) {
        in BLUETOOTH_TYPES -> d.address.trim().uppercase().takeLast(5)
        in USB_TYPES -> ""
        else -> d.address
    }

    /**
     * The choosable devices for [direction], one entry per key (first wins), in the given order.
     * For OUTPUT a Bluetooth device shows once per profile (A2DP or LE); SCO sinks are hidden,
     * because a preferred SCO output is silent outside the phone mode (the dialog uses the phone
     * mode itself, see DialogBluetooth). INPUT is unchanged.
     */
    fun entries(devices: List<AudioDeviceDesc>, direction: String): List<AudioDeviceEntry> {
        val seen = HashSet<String>()
        val out = ArrayList<AudioDeviceEntry>()
        for (d in devices) {
            val type = typeName(d, direction) ?: continue
            if (direction == OUTPUT && d.type == SCO_SINK) continue
            val key = keyOf(d)
            if (!seen.add(key)) continue
            out.add(AudioDeviceEntry(key, type, d.product.trim()))
        }
        return out
    }

    /**
     * The device to use: the one with [selected] if it is available, else `null` = system default
     * (also for no selection). Coming back means the same key again, so it is chosen again.
     */
    fun resolve(selected: String?, entries: List<AudioDeviceEntry>): AudioDeviceEntry? =
        if (selected == null) null else entries.firstOrNull { it.key == selected }

    private fun hash(address: String): String {
        if (address.isEmpty()) return ""
        val digest = MessageDigest.getInstance("SHA-256").digest(address.toByteArray())
        return digest.take(4).joinToString("") { "%02x".format(it) }
    }
}
