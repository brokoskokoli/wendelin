package app.wendelin

import android.app.usage.UsageStatsManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform side of `BatteryPlatform` (app/lib/platform/battery_platform.dart, WP56): battery
 * optimization, app standby bucket and vendor settings. Reused by the wake-word service (WP50).
 * No extra permission beyond REQUEST_IGNORE_BATTERY_OPTIMIZATIONS (K7: not for Play Store).
 */
class BatteryChannel(private val context: Context, messenger: BinaryMessenger) :
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
            "status" -> result.success(status())
            "requestIgnoreOptimizations" -> result.success(requestIgnore())
            "openBatterySettings" -> result.success(
                start(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) ||
                    start(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri())),
            )
            "openVendorSettings" -> result.success(openVendorSettings())
            else -> result.notImplemented()
        }
    }

    private fun vendor(): String? = BatteryVendors.vendor(Build.MANUFACTURER, Build.BRAND)

    private fun status(): Map<String, Any?> {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val usage = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
        val bucket = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) usage?.appStandbyBucket else null
        } catch (_: RuntimeException) {
            null
        }
        val vendor = vendor()
        return mapOf(
            "ignoring" to (pm?.isIgnoringBatteryOptimizations(context.packageName) == true),
            "bucket" to BatteryVendors.bucketName(bucket),
            "vendor" to vendor,
            "vendorSettings" to (vendorIntent() != null),
        )
    }

    private fun packageUri(): Uri = Uri.parse("package:${context.packageName}")

    private fun requestIgnore(): Boolean =
        start(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, packageUri())) ||
            start(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))

    /** First vendor page that resolves on this device. */
    private fun vendorIntent(): Intent? = BatteryVendors.pages(vendor()).firstNotNullOfOrNull {
        val intent = Intent().setComponent(ComponentName(it.pkg, it.cls))
        if (intent.resolveActivity(context.packageManager) != null) intent else null
    }

    private fun openVendorSettings(): Boolean = vendorIntent()?.let { start(it) } == true

    private fun start(intent: Intent): Boolean = try {
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (_: ActivityNotFoundException) {
        false
    } catch (_: SecurityException) {
        false
    }

    companion object {
        const val CHANNEL = "app.wendelin/battery"
    }
}
