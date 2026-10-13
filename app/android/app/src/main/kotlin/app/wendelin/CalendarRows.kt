package app.wendelin

import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Events
import android.provider.CalendarContract.Instances

/** Fields of an event sent by Dart (`createEvent`, `updateEvent`). */
class EventInput(
    val title: String?,
    val location: String?,
    val description: String?,
    val start: Long,
    val end: Long,
    val allDay: Boolean,
    val timeZone: String?,
) {
    companion object {
        fun from(args: ChannelArgs) = EventInput(
            title = args.string("title"),
            location = args.string("location"),
            description = args.string("description"),
            start = args.requireLong("start"),
            end = args.requireLong("end"),
            allDay = args.isTrue("allDay"),
            timeZone = args.string("timeZone"),
        )
    }
}

/** `WHERE` part and bound arguments of an instance query. */
class InstanceFilter(val selection: String, val args: List<String>)

/**
 * Cursor values to channel maps, time zones, durations and query building of
 * [CalendarChannel], without Android classes at run time (only inlined constants), so the
 * mapping can be tested on the JVM.
 */
object CalendarRows {
    /** Calendars the user may add events to (contributor and above). */
    fun isWritable(accessLevel: Int): Boolean = accessLevel >= Calendars.CAL_ACCESS_CONTRIBUTOR

    fun calendar(
        id: Long,
        name: String?,
        accessLevel: Int,
        accountName: String?,
        primary: Int,
    ): Map<String, Any?> = mapOf(
        "id" to id.toString(),
        "name" to (name ?: "Kalender"),
        "writable" to isWritable(accessLevel),
        "accountName" to accountName,
        "primary" to (primary == 1),
    )

    @Suppress("LongParameterList")
    fun event(
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

    /** End of a stored event: `DTEND`, or for recurring events start plus `DURATION`. */
    fun storedEnd(start: Long, dtEnd: Long?, duration: String?): Long =
        dtEnd ?: (start + durationMillis(duration))

    /** Length of an RFC 2445 duration such as `P3600S` or `P1D` in milliseconds. */
    fun durationMillis(value: String?): Long {
        if (value.isNullOrEmpty()) return 0
        val match = Regex("""^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$""")
            .matchEntire(value) ?: return 0
        fun part(i: Int) = match.groupValues[i].toLongOrNull() ?: 0
        val seconds = part(2) * 604800 + part(3) * 86400 + part(4) * 3600 + part(5) * 60 + part(6)
        return seconds * 1000 * (if (match.groupValues[1] == "-") -1 else 1)
    }

    /**
     * Time columns of an event. All-day events are stored in UTC (Android requires that), others
     * in the given zone or [defaultZone].
     */
    fun timeColumns(input: EventInput, defaultZone: String): Map<String, Any> = mapOf(
        Events.DTSTART to input.start,
        Events.DTEND to input.end,
        Events.ALL_DAY to (if (input.allDay) 1 else 0),
        Events.EVENT_TIMEZONE to (if (input.allDay) "UTC" else (input.timeZone ?: defaultZone)),
    )

    /** Cancelled occurrences are hidden; `null` if an empty calendar list selects nothing. */
    fun instanceFilter(calendarIds: List<String>?): InstanceFilter? {
        var selection = "(${Instances.STATUS} IS NULL OR ${Instances.STATUS} != ?)"
        val args = mutableListOf(Instances.STATUS_CANCELED.toString())
        if (calendarIds != null) {
            if (calendarIds.isEmpty()) return null
            selection += " AND ${Instances.CALENDAR_ID} IN (${calendarIds.joinToString(",") { "?" }})"
            args.addAll(calendarIds)
        }
        return InstanceFilter(selection, args)
    }

    /** Display name of an attendee: name if not blank, else e-mail address. */
    fun attendeeName(name: String?, email: String?): String? =
        name?.takeIf { it.isNotBlank() } ?: email

    /** Sets `attendees` of every row from [byEvent] (event id to names). */
    fun attachAttendees(rows: List<MutableMap<String, Any?>>, byEvent: Map<String, List<String>>) {
        for (row in rows) {
            row["attendees"] = byEvent[row["id"] as String] ?: emptyList<String>()
        }
    }
}
