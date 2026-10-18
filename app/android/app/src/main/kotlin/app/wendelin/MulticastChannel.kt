package app.wendelin

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform side of `MdnsHaDiscovery` (app/lib/platform/ha_discovery.dart, WP91): holds a Wi-Fi
 * `MulticastLock` while the app searches for Home Assistant via mDNS; many devices otherwise drop
 * multicast packets. Needs CHANGE_WIFI_MULTICAST_STATE (normal permission, no prompt).
 */
class MulticastChannel(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val lock: WifiManager.MulticastLock? =
        (context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager)
            ?.createMulticastLock("wendelin-mdns")
            ?.also { it.setReferenceCounted(false) }

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        release()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "acquire" -> {
                lock?.takeIf { !it.isHeld }?.acquire()
                result.success(null)
            }
            "release" -> {
                release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun release() {
        lock?.takeIf { it.isHeld }?.release()
    }

    companion object {
        const val CHANNEL = "app.wendelin/multicast"
    }
}
