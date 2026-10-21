package app.wendelin

import android.app.AlarmManager
import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform side of `AndroidAlarmPort` (app/lib/platform/android_alarm_port.dart, WP119): the next
 * alarm of any clock app from [AlarmManager.getNextAlarmClock]. Android offers no list of alarms
 * and the call needs no permission. `nextAlarm` answers `{at: <epoch millis>}`, or `null` without
 * an alarm.
 */
class AlarmChannel(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val manager = context.getSystemService(AlarmManager::class.java)

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "nextAlarm" -> result.success(
                try {
                    NextAlarm.reply(manager?.nextAlarmClock?.triggerTime)
                } catch (_: RuntimeException) {
                    null
                },
            )
            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL = "app.wendelin/alarm"
    }
}

/** The reply of `nextAlarm`, without Android. */
object NextAlarm {
    /** `{at: millis}` for a valid trigger time, else `null` (no alarm or nonsense). */
    fun reply(triggerMillis: Long?): Map<String, Any>? =
        if (triggerMillis != null && triggerMillis > 0) mapOf("at" to triggerMillis) else null
}
