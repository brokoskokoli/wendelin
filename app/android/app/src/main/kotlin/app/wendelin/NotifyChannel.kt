package app.wendelin

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform side of `ChannelAttestationNotifier` (app/lib/platform/channel_notifier.dart): one
 * system notification for a failed TEE check after the answer (WP52, GPU mode „Nachher“). Posts
 * only with the notification permission (Android 13+), asked for when the user chooses the mode.
 * Title and text are secret-free and contain no conversation content.
 */
class NotifyChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private var pendingPermission: MethodChannel.Result? = null
    private var nextId = 1

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    fun onPermissionResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != PERMISSION_REQUEST) return
        val result = pendingPermission ?: return
        pendingPermission = null
        result.success(grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasPermission" -> result.success(hasPermission())
            "requestPermission" -> requestPermission(result)
            "show" -> show(call.argument<String>("title"), call.argument<String>("text"), result)
            else -> result.notImplemented()
        }
    }

    private fun hasPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestPermission(result: MethodChannel.Result) {
        if (hasPermission()) {
            result.success(true)
            return
        }
        if (pendingPermission != null) {
            result.error("failed", "busy", null)
            return
        }
        pendingPermission = result
        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
    }

    private fun show(title: String?, text: String?, result: MethodChannel.Result) {
        if (title == null || text == null) {
            result.error("bad_args", "title/text fehlen", null)
            return
        }
        if (!hasPermission()) {
            result.success(false)
            return
        }
        val manager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "TEE-Prüfung", NotificationManager.IMPORTANCE_HIGH),
        )
        val notification = Notification.Builder(activity, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_wendelin)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .build()
        manager.notify(nextId++, notification)
        result.success(true)
    }

    companion object {
        const val CHANNEL = "app.wendelin/notify"
        private const val CHANNEL_ID = "attestation"
        private const val PERMISSION_REQUEST = 4712
    }
}
