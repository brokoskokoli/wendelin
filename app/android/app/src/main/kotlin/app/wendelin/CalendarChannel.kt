package app.wendelin

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Platform side of `DeviceCalendarPort` (app/lib/platform/device_calendar_port.dart).
 *
 * Plain CalendarContract queries and writes; overlap filtering and the choice of the
 * default calendar happen in Dart. Errors are reported with the codes
 * `permissionDenied`, `notFound`, `readOnly` and `failed`.
 */
class CalendarChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val io: ExecutorService = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val store = CalendarStore(activity.contentResolver)
    private var pendingPermission: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        io.shutdown()
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
            else -> io.execute {
                val reply: () -> Unit = try {
                    if (!hasPermission()) throw CalendarError("permissionDenied")
                    val value = handle(call)
                    ({ result.success(value) })
                } catch (e: CalendarError) {
                    ({ result.error(e.code, e.code, null) })
                } catch (e: SecurityException) {
                    ({ result.error("permissionDenied", "permissionDenied", null) })
                } catch (e: Exception) {
                    ({ result.error("failed", e.javaClass.simpleName, null) })
                }
                main.post(reply)
            }
        }
    }

    private fun handle(call: MethodCall): Any? {
        val args = ChannelArgs.of(call.arguments)
        return when (call.method) {
            "listCalendars" -> store.listCalendars()
            "listEvents" -> store.listEvents(
                args.requireLong("start"),
                args.requireLong("end"),
                args.stringList("calendarIds"),
            )
            "getEvent" -> store.getEvent(args.requireString("id"))
            "createEvent" -> store.createEvent(args.requireString("calendarId"), EventInput.from(args))
            "updateEvent" -> store.updateEvent(args.requireString("id"), EventInput.from(args))
            "deleteEvent" -> store.deleteEvent(args.requireString("id"))
            else -> throw CalendarError("failed")
        }
    }

    private fun hasPermission(): Boolean = PERMISSIONS.all {
        activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
    }

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
        activity.requestPermissions(PERMISSIONS, PERMISSION_REQUEST)
    }

    companion object {
        const val CHANNEL = "app.wendelin/calendar"
        private const val PERMISSION_REQUEST = 4711
        private val PERMISSIONS = arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR)
    }
}
