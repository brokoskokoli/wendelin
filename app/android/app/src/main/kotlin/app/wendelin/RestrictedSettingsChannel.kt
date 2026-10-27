package app.wendelin

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform side of `RestrictedSettingsPlatform` (app/lib/platform/restricted_settings_platform.dart,
 * WP159): Android 13+ blocks SMS permission and notification access for apps installed from a file
 * ("restricted settings", Android 15: Enhanced Confirmation Mode). Reads only the install source;
 * no extra permission.
 *
 * The AppOp `android:access_restricted_settings` is deliberately NOT read: measured on Android 15,
 * every `AppOpsManager.checkOp*` variant throws a SecurityException for a normal app
 * (`verifyIncomingOp`: needs MANAGE_APPOPS or GET_APP_OPS_STATS), so the restriction cannot be
 * detected. The Dart side therefore shows a conditional hint based on the install source.
 */
class RestrictedSettingsChannel(private val context: Context, messenger: BinaryMessenger) :
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
            "restrictedSettings" -> result.success(state())
            "openAppInfo" -> result.success(openAppInfo())
            else -> result.notImplemented()
        }
    }

    private fun state(): Map<String, Any?> = mapOf(
        "sdk" to Build.VERSION.SDK_INT,
        "installSource" to RestrictedSettingsMapping.installSource(
            Build.VERSION.SDK_INT,
            readPackageSource(),
        ),
    )

    /** `InstallSourceInfo.getPackageSource()` (API 33+), `null` if unreadable. */
    private fun readPackageSource(): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return null
        return try {
            context.packageManager.getInstallSourceInfo(context.packageName).packageSource
        } catch (_: PackageManager.NameNotFoundException) {
            null
        } catch (_: RuntimeException) {
            null
        }
    }

    private fun openAppInfo(): Boolean = try {
        val uri = Uri.parse("package:${context.packageName}")
        context.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, uri)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        true
    } catch (_: ActivityNotFoundException) {
        false
    } catch (_: SecurityException) {
        false
    }

    companion object {
        const val CHANNEL = "app.wendelin/restricted_settings"
    }
}

/** Pure mapping of the raw Android values (unit-tested). */
object RestrictedSettingsMapping {
    /**
     * `file` for an APK installed from a (downloaded) file, `session` for a store or the
     * installer API, `unknown` below API 33 or if unreadable. `adb install` reports UNSPECIFIED
     * and counts as `session` (measured: not restricted).
     */
    fun installSource(sdk: Int, packageSource: Int?): String = when {
        sdk < 33 || packageSource == null -> "unknown"
        packageSource == PACKAGE_SOURCE_LOCAL_FILE ||
            packageSource == PACKAGE_SOURCE_DOWNLOADED_FILE -> "file"
        else -> "session"
    }

    // PackageInstaller.PACKAGE_SOURCE_* (API 33/34); literals keep this class testable on the JVM.
    const val PACKAGE_SOURCE_LOCAL_FILE = 3
    const val PACKAGE_SOURCE_DOWNLOADED_FILE = 4
}
