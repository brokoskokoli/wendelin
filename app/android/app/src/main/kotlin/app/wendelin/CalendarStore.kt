package app.wendelin

import android.content.ContentResolver
import android.content.ContentUris
import android.content.ContentValues
import android.provider.CalendarContract.Attendees
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Events
import android.provider.CalendarContract.Instances

/** A calendar operation failed with a channel error code (`notFound`, `readOnly`, `failed`). */
class CalendarError(val code: String) : Exception(code)

/** CalendarContract queries and writes for [CalendarChannel]; the mapping is in [CalendarRows]. */
class CalendarStore(private val resolver: ContentResolver) {

    fun listCalendars(): List<Map<String, Any?>> {
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
                out.add(CalendarRows.calendar(c.getLong(0), c.getString(1), c.getInt(2), c.getString(3), c.getInt(4)))
            }
        }
        return out
    }

    private fun calendarWritable(id: String): Boolean {
        val uri = ContentUris.withAppendedId(Calendars.CONTENT_URI, id.toLong())
        resolver.query(uri, arrayOf(Calendars.CALENDAR_ACCESS_LEVEL), null, null, null)?.use { c ->
            if (!c.moveToFirst()) throw CalendarError("notFound")
            return CalendarRows.isWritable(c.getInt(0))
        }
        throw CalendarError("notFound")
    }

    fun listEvents(start: Long, end: Long, calendarIds: List<String>?): List<Map<String, Any?>> {
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
        val filter = CalendarRows.instanceFilter(calendarIds) ?: return emptyList()
        val rows = mutableListOf<MutableMap<String, Any?>>()
        resolver.query(
            builder.build(),
            projection,
            filter.selection,
            filter.args.toTypedArray(),
            "${Instances.BEGIN} ASC",
        )?.use { c ->
            while (c.moveToNext()) {
                rows.add(
                    CalendarRows.event(
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

    fun getEvent(id: String): Map<String, Any?>? {
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
                val end = CalendarRows.storedEnd(start, if (c.isNull(4)) null else c.getLong(4), c.getString(5))
                rows.add(
                    CalendarRows.event(
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

    fun createEvent(calendarId: String, input: EventInput): Map<String, Any?>? {
        if (!calendarWritable(calendarId)) throw CalendarError("readOnly")
        val values = timeValues(input).apply {
            put(Events.CALENDAR_ID, calendarId.toLong())
            put(Events.TITLE, input.title)
            put(Events.EVENT_LOCATION, input.location)
            put(Events.DESCRIPTION, input.description)
        }
        val uri = resolver.insert(Events.CONTENT_URI, values) ?: throw CalendarError("failed")
        return getEvent(ContentUris.parseId(uri).toString())
    }

    fun updateEvent(id: String, input: EventInput): Map<String, Any?>? {
        val existing = getEvent(id) ?: throw CalendarError("notFound")
        if (!calendarWritable(existing["calendarId"] as String)) throw CalendarError("readOnly")
        // Series: only text fields (the integration rejects time changes on series).
        val values = if (existing["recurring"] == true) ContentValues() else timeValues(input)
        values.put(Events.TITLE, input.title)
        values.put(Events.EVENT_LOCATION, input.location ?: "")
        values.put(Events.DESCRIPTION, input.description ?: "")
        val uri = ContentUris.withAppendedId(Events.CONTENT_URI, id.toLong())
        if (resolver.update(uri, values, null, null) == 0) throw CalendarError("notFound")
        return getEvent(id)
    }

    fun deleteEvent(id: String): Any? {
        val existing = getEvent(id) ?: throw CalendarError("notFound")
        if (!calendarWritable(existing["calendarId"] as String)) throw CalendarError("readOnly")
        val uri = ContentUris.withAppendedId(Events.CONTENT_URI, id.toLong())
        if (resolver.delete(uri, null, null) == 0) throw CalendarError("notFound")
        return null
    }

    private fun timeValues(input: EventInput) = ContentValues().apply {
        for ((key, value) in CalendarRows.timeColumns(input, java.util.TimeZone.getDefault().id)) {
            when (value) {
                is Long -> put(key, value)
                is Int -> put(key, value)
                else -> put(key, value as String)
            }
        }
    }

    private fun addAttendees(rows: List<MutableMap<String, Any?>>) {
        if (rows.isEmpty()) return
        val ids = rows.map { it["id"] as String }.distinct()
        val byEvent = mutableMapOf<String, MutableList<String>>()
        // SQLite allows at most 999 bound parameters per statement.
        for (chunk in ids.chunked(ATTENDEE_CHUNK)) {
            readAttendees(chunk, byEvent)
        }
        CalendarRows.attachAttendees(rows, byEvent)
    }

    private fun readAttendees(ids: List<String>, byEvent: MutableMap<String, MutableList<String>>) {
        resolver.query(
            Attendees.CONTENT_URI,
            arrayOf(Attendees.EVENT_ID, Attendees.ATTENDEE_NAME, Attendees.ATTENDEE_EMAIL),
            "${Attendees.EVENT_ID} IN (${ids.joinToString(",") { "?" }})",
            ids.toTypedArray(),
            null,
        )?.use { c ->
            while (c.moveToNext()) {
                val name = CalendarRows.attendeeName(c.getString(1), c.getString(2))
                if (name != null) {
                    byEvent.getOrPut(c.getLong(0).toString()) { mutableListOf() }.add(name)
                }
            }
        }
    }

    private companion object {
        const val ATTENDEE_CHUNK = 500
    }
}
