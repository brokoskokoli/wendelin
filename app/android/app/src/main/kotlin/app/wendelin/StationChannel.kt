package app.wendelin

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform side of `StationPort` (app/lib/platform/channel_station_port.dart): starts the station
 * mode and reports the lock state; in the station's own engine it also sends the ambient light
 * (`ambient`) to Dart.
 */
class StationChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    /** The room became dark or bright again. */
    fun ambient(dark: Boolean) {
        channel.invokeMethod("ambient", mapOf("dark" to dark))
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isLocked" -> result.success(isLocked(activity))
            "start" -> {
                // The voice command (and the button) work on an unlocked device only.
                if (!StationPolicy.voiceStartAllowed(isLocked(activity))) {
                    result.error("locked", "device is locked", null)
                    return
                }
                activity.startActivity(launchIntent(activity))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL = "app.wendelin/station"

        fun isLocked(context: Context): Boolean =
            (context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager).isKeyguardLocked

        fun launchIntent(context: Context): Intent =
            Intent(context, StationActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
    }
}
