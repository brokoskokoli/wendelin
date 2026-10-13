package app.wendelin

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform side of `ChannelAppPresencePort` (app/lib/platform/channel_app_presence_port.dart):
 * whether another app is installed. Android 11+ only shows packages declared in `<queries>`
 * of the manifest (no QUERY_ALL_PACKAGES); everything else counts as not installed.
 */
class AppsChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isInstalled" -> {
                val pkg = call.argument<String>("package")
                if (pkg.isNullOrEmpty()) {
                    result.error("bad_args", "package fehlt", null)
                } else {
                    result.success(isInstalled(pkg))
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun isInstalled(pkg: String): Boolean {
        val pm = context.packageManager
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getPackageInfo(pkg, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(pkg, 0)
            }
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    companion object {
        const val CHANNEL = "app.wendelin/apps"
    }
}
