package app.wendelin

import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Events
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Cursor values to channel maps, durations, time zones and query building of the calendar. */
class CalendarRowsTest {
    private fun event(
        start: Long = 1_000,
        end: Long = 2_000,
        availability: Int = Events.AVAILABILITY_BUSY,
        rrule: String? = null,
        title: String? = "Zahnarzt",
    ) = CalendarRows.event(
        id = 7,
        calendarId = 3,
        title = title,
        start = start,
        end = end,
        allDay = false,
        location = "Praxis",
        description = null,
        availability = availability,
        rrule = rrule,
        timeZone = "Europe/Berlin",
    )

    @Test
    fun eventMapUsesStringIdsAndKeepsStartBeforeEnd() {
        val e = event()
        assertEquals("7", e["id"])
        assertEquals("3", e["calendarId"])
        assertEquals(1_000L, e["start"])
        assertEquals(2_000L, e["end"])
        assertEquals("Europe/Berlin", e["timeZone"])
        assertEquals(emptyList<String>(), e["attendees"])
    }

    @Test
    fun endNeverBeforeStart() {
        assertEquals(5_000L, event(start = 5_000, end = 1_000)["end"])
    }

    @Test
    fun missingTitleBecomesEmpty() {
        assertEquals("", event(title = null)["title"])
    }

    @Test
    fun busyUnlessAvailabilityFree() {
        assertEquals(true, event(availability = Events.AVAILABILITY_BUSY)["busy"])
        assertEquals(true, event(availability = Events.AVAILABILITY_TENTATIVE)["busy"])
        assertEquals(false, event(availability = Events.AVAILABILITY_FREE)["busy"])
    }

    @Test
    fun recurringOnlyWithNonEmptyRule() {
        assertEquals(true, event(rrule = "FREQ=WEEKLY")["recurring"])
        assertEquals(false, event(rrule = "")["recurring"])
        assertEquals(false, event(rrule = null)["recurring"])
    }

    @Test
    fun calendarMapNamesWritableAndPrimary() {
        val ro = CalendarRows.calendar(1, null, Calendars.CAL_ACCESS_READ, "a@b", 0)
        assertEquals("Kalender", ro["name"])
        assertEquals(false, ro["writable"])
        assertEquals(false, ro["primary"])
        val rw = CalendarRows.calendar(2, "Privat", Calendars.CAL_ACCESS_CONTRIBUTOR, null, 1)
        assertEquals("2", rw["id"])
        assertEquals(true, rw["writable"])
        assertEquals(true, rw["primary"])
        assertTrue(CalendarRows.isWritable(Calendars.CAL_ACCESS_OWNER))
        assertFalse(CalendarRows.isWritable(Calendars.CAL_ACCESS_EDITOR - 1000))
    }

    @Test
    fun durationTable() {
        val cases = mapOf(
            null to 0L,
            "" to 0L,
            "PT3600S" to 3_600_000L,
            "PT1H" to 3_600_000L,
            "PT1H30M" to 5_400_000L,
            "P1D" to 86_400_000L,
            "P1W" to 604_800_000L,
            "P1DT2H" to 93_600_000L,
            "-PT30S" to -30_000L,
            "garbage" to 0L,
        )
        for ((value, millis) in cases) assertEquals(value, millis, CalendarRows.durationMillis(value))
    }

    @Test
    fun storedEndPrefersDtEnd() {
        assertEquals(9_000L, CalendarRows.storedEnd(1_000, 9_000, "PT1H"))
        assertEquals(1_000L + 3_600_000L, CalendarRows.storedEnd(1_000, null, "PT1H"))
        assertEquals(1_000L, CalendarRows.storedEnd(1_000, null, null))
    }

    @Test
    fun timeColumnsKeepStartAndEnd() {
        val input = EventInput("t", null, null, start = 10, end = 20, allDay = false, timeZone = "Asia/Tokyo")
        val c = CalendarRows.timeColumns(input, "Europe/Berlin")
        assertEquals(10L, c[Events.DTSTART])
        assertEquals(20L, c[Events.DTEND])
        assertEquals(0, c[Events.ALL_DAY])
        assertEquals("Asia/Tokyo", c[Events.EVENT_TIMEZONE])
    }

    @Test
    fun allDayIsStoredInUtcAndMissingZoneUsesDefault() {
        val allDay = EventInput("t", null, null, 10, 20, allDay = true, timeZone = "Asia/Tokyo")
        val c = CalendarRows.timeColumns(allDay, "Europe/Berlin")
        assertEquals(1, c[Events.ALL_DAY])
        assertEquals("UTC", c[Events.EVENT_TIMEZONE])
        val noZone = EventInput("t", null, null, 10, 20, allDay = false, timeZone = null)
        assertEquals("Europe/Berlin", CalendarRows.timeColumns(noZone, "Europe/Berlin")[Events.EVENT_TIMEZONE])
    }

    @Test
    fun eventInputReadsFieldsAndRequiresTimes() {
        val input = EventInput.from(
            ChannelArgs.of(
                mapOf("title" to "x", "start" to 1, "end" to 2L, "allDay" to true, "location" to null),
            ),
        )
        assertEquals("x", input.title)
        assertEquals(1L, input.start)
        assertEquals(2L, input.end)
        assertTrue(input.allDay)
        assertNull(input.location)
        try {
            EventInput.from(ChannelArgs.of(mapOf("title" to "x", "start" to 1)))
            org.junit.Assert.fail("end is required")
        } catch (e: ArgumentException) {
            assertEquals("end", e.key)
        }
    }

    @Test
    fun instanceFilterHidesCancelledAndBindsCalendarIds() {
        val all = CalendarRows.instanceFilter(null)!!
        assertEquals(listOf(Events.STATUS_CANCELED.toString()), all.args)
        assertFalse(all.selection.contains("IN ("))
        val some = CalendarRows.instanceFilter(listOf("1", "2"))!!
        assertTrue(some.selection.endsWith("IN (?,?)"))
        assertEquals(listOf(Events.STATUS_CANCELED.toString(), "1", "2"), some.args)
        assertNull(CalendarRows.instanceFilter(emptyList()))
    }

    @Test
    fun attendeeNamePrefersNameOverEmail() {
        assertEquals("Anna", CalendarRows.attendeeName("Anna", "a@x"))
        assertEquals("a@x", CalendarRows.attendeeName("  ", "a@x"))
        assertEquals("a@x", CalendarRows.attendeeName(null, "a@x"))
        assertNull(CalendarRows.attendeeName(null, null))
    }

    @Test
    fun attendeesAreAttachedByEventId() {
        val rows = listOf(event(), CalendarRows.event(8, 3, "b", 1, 2, false, null, null, 0, null, null))
        CalendarRows.attachAttendees(rows, mapOf("7" to listOf("Anna", "Ben")))
        assertEquals(listOf("Anna", "Ben"), rows[0]["attendees"])
        assertEquals(emptyList<String>(), rows[1]["attendees"])
    }
}
