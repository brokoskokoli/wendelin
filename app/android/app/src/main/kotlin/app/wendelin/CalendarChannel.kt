package app.wendelin

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.ContentValues
import android.content.pm.PackageManager
import android.database.Cursor
import android.os.Handler
import android.os.Looper
import android.provider.CalendarContract.Attendees
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Events
import android.provider.CalendarContract.Instances
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
                    if (!hasPermission()) throw ChannelError("permissionDenied")
                    val value = handle(call)
                    ({ result.success(value) })
                } catch (e: ChannelError) {
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

    private fun handle(call: MethodCall): Any? = when (call.method) {
        "listCalendars" -> listCalendars()
        "listEvents" -> listEvents(
            call.argument<Number>("start")!!.toLong(),
            call.argument<Number>("end")!!.toLong(),
            call.argument<List<String>>("calendarIds"),
        )
        "getEvent" -> getEvent(call.argument<String>("id")!!)
        "createEvent" -> createEvent(call)
        "updateEvent" -> updateEvent(call)
        "deleteEvent" -> deleteEvent(call.argument<String>("id")!!)
        else -> throw ChannelError("failed")
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

    private val resolver get() = activity.contentResolver

    private fun listCalendars(): List<Map<String, Any?>> {
        val projection = arrayOf(
            Calendars._ID,
            Calendars.CALENDAR_DISPLAY_NAME,
            Calendars.CALENDAR_ACCESS_LEVEL,
            Calendars.ACCOUNT_NAME,
            Calendars.IS_PRIMARY,
        )
        val out = mutableListOf<Map<String, Any?>>()
        resolver.query(Calendars.CONTENT_URI, projection, "${Calendars.VISIBLE} = 1", null, null)?.use { c ->
            while (c.moveToNext()) {
                out.add(
                    mapOf(
                        "id" to c.getLong(0).toString(),
                        "name" to (c.getString(1) ?: "Kalender"),
                        "writable" to (c.getInt(2) >= Calendars.CAL_ACCESS_CONTRIBUTOR),
                        "accountName" to c.getString(3),
                        "primary" to (c.getInt(4) == 1),
                    ),
                )
            }
        }
        return out
    }

    private fun calendarWritable(id: String): Boolean {
        val uri = ContentUris.withAppendedId(Calendars.CONTENT_URI, id.toLong())
        resolver.query(uri, arrayOf(Calendars.CALENDAR_ACCESS_LEVEL), null, null, null)?.use { c ->
            if (!c.moveToFirst()) throw ChannelError("notFound")
            return c.getInt(0) >= Calendars.CAL_ACCESS_CONTRIBUTOR
        }
        throw ChannelError("notFound")
    }

    private fun listEvents(start: Long, end: Long, calendarIds: List<String>?): List<Map<String, Any?>> {
        val builder = Instances.CONTENT_URI.buildUpon()
        ContentUris.appendId(builder, start)
        ContentUris.appendId(builder, end)
        val projection = arrayOf(
            Instances.EVENT_ID,
            Instances.CALENDAR_ID,
            Instances.TITLE,
            Instances.BEGIN,
            Instances.END,
            Instances.ALL_DAY,
            Instances.EVENT_LOCATION,
            Instances.DESCRIPTION,
            Instances.AVAILABILITY,
            Instances.RRULE,
            Instances.EVENT_TIMEZONE,
        )
        var selection: String? = null
        var args: Array<String>? = null
        if (calendarIds != null) {
            if (calendarIds.isEmpty()) return emptyList()
            selection = "${Instances.CALENDAR_ID} IN (${calendarIds.joinToString(",") { "?" }})"
            args = calendarIds.toTypedArray()
        }
        val rows = mutableListOf<MutableMap<String, Any?>>()
        resolver.query(builder.build(), projection, selection, args, "${Instances.BEGIN} ASC")?.use { c ->
            while (c.moveToNext()) {
                rows.add(
                    eventMap(
                        id = c.getLong(0),
                        calendarId = c.getLong(1),
                        title = c.getString(2),
                        start = c.getLong(3),
                        end = c.getLong(4),
                        allDay = c.getInt(5) == 1,
                        location = c.getString(6),
                        description = c.getString(7),
                        availability = c.getInt(8),
                        rrule = c.getString(9),
                        timeZone = c.getString(10),
                    ),
                )
            }
        }
        addAttendees(rows)
        return rows
    }

    private fun getEvent(id: String): Map<String, Any?>? {
        val projection = arrayOf(
            Events._ID,
            Events.CALENDAR_ID,
            Events.TITLE,
            Events.DTSTART,
            Events.DTEND,
            Events.DURATION,
            Events.ALL_DAY,
            Events.EVENT_LOCATION,
            Events.DESCRIPTION,
            Events.AVAILABILITY,
            Events.RRULE,
            Events.EVENT_TIMEZONE,
        )
        val longId = id.toLongOrNull() ?: return null
        val rows = mutableListOf<MutableMap<String, Any?>>()
        resolver.query(
            Events.CONTENT_URI,
            projection,
            "${Events._ID} = ? AND ${Events.DELETED} = 0",
            arrayOf(longId.toString()),
            null,
        )?.use { c ->
            if (c.moveToFirst()) {
                val start = c.getLong(3)
                val end = if (c.isNull(4)) start + durationMillis(c.getString(5)) else c.getLong(4)
                rows.add(
                    eventMap(
                        id = c.getLong(0),
                        calendarId = c.getLong(1),
                        title = c.getString(2),
                        start = start,
                        end = end,
                        allDay = c.getInt(6) == 1,
                        location = c.getString(7),
                        description = c.getString(8),
                        availability = c.getInt(9),
                        rrule = c.getString(10),
                        timeZone = c.getString(11),
                    ),
                )
            }
        }
        addAttendees(rows)
        return rows.firstOrNull()
    }

    private fun createEvent(call: MethodCall): Map<String, Any?>? {
        val calendarId = call.argument<String>("calendarId")!!
        if (!calendarWritable(calendarId)) throw ChannelError("readOnly")
        val values = timeValues(call).apply {
            put(Events.CALENDAR_ID, calendarId.toLong())
            put(Events.TITLE, call.argument<String>("title"))
            put(Events.EVENT_LOCATION, call.argument<String>("location"))
            put(Events.DESCRIPTION, call.argument<String>("description"))
        }
        val uri = resolver.insert(Events.CONTENT_URI, values) ?: throw ChannelError("failed")
        return getEvent(ContentUris.parseId(uri).toString())
    }

    private fun updateEvent(call: MethodCall): Map<String, Any?>? {
        val id = call.argument<String>("id")!!
        val existing = getEvent(id) ?: throw ChannelError("notFound")
        if (!calendarWritable(existing["calendarId"] as String)) throw ChannelError("readOnly")
        // Series: only text fields (the integration rejects time changes on series).
        val values = if (existing["recurring"] == true) ContentValues() else timeValues(call)
        values.put(Events.TITLE, call.argument<String>("title"))
        values.put(Events.EVENT_LOCATION, call.argument<String>("location") ?: "")
        values.put(Events.DESCRIPTION, call.argument<String>("description") ?: "")
        val uri = ContentUris.withAppendedId(Events.CONTENT_URI, id.toLong())
        if (resolver.update(uri, values, null, null) == 0) throw ChannelError("notFound")
        return getEvent(id)
    }

    private fun deleteEvent(id: String): Any? {
        getEvent(id) ?: throw ChannelError("notFound")
        val uri = ContentUris.withAppendedId(Events.CONTENT_URI, id.toLong())
        if (resolver.delete(uri, null, null) == 0) throw ChannelError("notFound")
        return null
    }

    private fun timeValues(call: MethodCall) = ContentValues().apply {
        val allDay = call.argument<Boolean>("allDay") == true
        put(Events.DTSTART, call.argument<Number>("start")!!.toLong())
        put(Events.DTEND, call.argument<Number>("end")!!.toLong())
        put(Events.ALL_DAY, if (allDay) 1 else 0)
        put(Events.EVENT_TIMEZONE, if (allDay) "UTC" else (call.argument<String>("timeZone") ?: java.util.TimeZone.getDefault().id))
    }

    private fun eventMap(
        id: Long,
        calendarId: Long,
        title: String?,
        start: Long,
        end: Long,
        allDay: Boolean,
        location: String?,
        description: String?,
        availability: Int,
        rrule: String?,
        timeZone: String?,
    ): MutableMap<String, Any?> = mutableMapOf(
        "id" to id.toString(),
        "calendarId" to calendarId.toString(),
        "title" to (title ?: ""),
        "start" to start,
        "end" to maxOf(end, start),
        "allDay" to allDay,
        "location" to location,
        "description" to description,
        "attendees" to emptyList<String>(),
        "busy" to (availability != Events.AVAILABILITY_FREE),
        "recurring" to !rrule.isNullOrEmpty(),
        "timeZone" to timeZone,
    )

    private fun addAttendees(rows: List<MutableMap<String, Any?>>) {
        if (rows.isEmpty()) return
        val ids = rows.map { it["id"] as String }.distinct()
        val byEvent = mutableMapOf<String, MutableList<String>>()
        val cursor: Cursor? = resolver.query(
            Attendees.CONTENT_URI,
            arrayOf(Attendees.EVENT_ID, Attendees.ATTENDEE_NAME, Attendees.ATTENDEE_EMAIL),
            "${Attendees.EVENT_ID} IN (${ids.joinToString(",") { "?" }})",
            ids.toTypedArray(),
            null,
        )
        cursor?.use { c ->
            while (c.moveToNext()) {
                val name = c.getString(1)?.takeIf { it.isNotBlank() } ?: c.getString(2)
                if (name != null) {
                    byEvent.getOrPut(c.getLong(0).toString()) { mutableListOf() }.add(name)
                }
            }
        }
        for (row in rows) {
            row["attendees"] = byEvent[row["id"] as String] ?: emptyList<String>()
        }
    }

    private class ChannelError(val code: String) : Exception(code)

    companion object {
        const val CHANNEL = "app.wendelin/calendar"
        private const val PERMISSION_REQUEST = 4711
        private val PERMISSIONS = arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR)

        /** Length of an RFC 2445 duration such as `P3600S` or `P1D` in milliseconds. */
        fun durationMillis(value: String?): Long {
            if (value.isNullOrEmpty()) return 0
            val match = Regex("""^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$""")
                .matchEntire(value) ?: return 0
            fun part(i: Int) = match.groupValues[i].toLongOrNull() ?: 0
            val seconds = part(2) * 604800 + part(3) * 86400 + part(4) * 3600 + part(5) * 60 + part(6)
            return seconds * 1000 * (if (match.groupValues[1] == "-") -1 else 1)
        }
    }
}
