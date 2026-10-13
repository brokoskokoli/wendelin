package app.wendelin

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform side of `ChannelNetworkStatus` (app/lib/platform/channel_network_status.dart):
 * connectivity for the routing condition `network` from [ConnectivityManager] (no Play
 * Services). `state` answers `offline`, `online` or `metered`; changes of the default network
 * are pushed as `changed`.
 */
class NetworkChannel(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val manager = context.getSystemService(ConnectivityManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private var registered = false

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = push()

        // The lost network may still be reported as active for a moment:
        // it counts as gone, so without a successor the state is offline.
        override fun onLost(network: Network) = push(lost = network)
        override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) = push()
    }

    init {
        channel.setMethodCallHandler(this)
        registered = try {
            manager?.registerDefaultNetworkCallback(callback)
            manager != null
        } catch (_: SecurityException) {
            false
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        if (registered) {
            try {
                manager?.unregisterNetworkCallback(callback)
            } catch (_: IllegalArgumentException) {
                // Already unregistered.
            }
            registered = false
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "state" -> result.success(state())
            else -> result.notImplemented()
        }
    }

    /** Current state; [lost] is a network that just went away. */
    private fun state(lost: Network? = null): String {
        val cm = manager ?: return ONLINE
        val network = cm.activeNetwork ?: return OFFLINE
        if (network == lost) return OFFLINE
        val caps = cm.getNetworkCapabilities(network) ?: return OFFLINE
        if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) return OFFLINE
        // Captive portal or no working internet: not online.
        if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) return OFFLINE
        return if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)) ONLINE else METERED
    }

    private fun push(lost: Network? = null) {
        main.post { if (registered) channel.invokeMethod("changed", state(lost)) }
    }

    companion object {
        const val CHANNEL = "app.wendelin/network"
        private const val OFFLINE = "offline"
        private const val ONLINE = "online"
        private const val METERED = "metered"
    }
}
