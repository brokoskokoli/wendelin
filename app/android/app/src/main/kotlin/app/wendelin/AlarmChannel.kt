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
            "nextAlarm" -> NextAlarm.answer(
                {
                    val am = manager ?: throw IllegalStateException("no AlarmManager")
                    am.nextAlarmClock?.triggerTime
                },
                { result.success(it) },
                { code, message -> result.error(code, message, null) },
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

    /**
     * Reads the trigger time with [read] and reports it through [success] (`null` = no alarm) or,
     * if the read fails (also a missing [AlarmManager] or a `SecurityException`), through
     * [error] with code `failed`. A failed read is never reported as "no alarm".
     */
    fun answer(
        read: () -> Long?,
        success: (Map<String, Any>?) -> Unit,
        error: (String, String) -> Unit,
    ) {
        val millis = try {
            read()
        } catch (e: RuntimeException) {
            error("failed", e.message ?: "nextAlarm failed")
            return
        }
        success(reply(millis))
    }
}
