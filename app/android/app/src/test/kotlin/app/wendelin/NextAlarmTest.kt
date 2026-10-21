package app.wendelin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The reply of the `nextAlarm` call (WP119). */
class NextAlarmTest {
    @Test
    fun noAlarmGivesNull() {
        assertNull(NextAlarm.reply(null))
    }

    @Test
    fun nonsenseTimesGiveNull() {
        assertNull(NextAlarm.reply(0L))
        assertNull(NextAlarm.reply(-5L))
    }

    @Test
    fun triggerTimeIsPassedAsEpochMillis() {
        assertEquals(mapOf("at" to 1_800_000_000_000L), NextAlarm.reply(1_800_000_000_000L))
    }

    @Test
    fun failedReadIsAnErrorNotNoAlarm() {
        var success: Map<String, Any>? = mapOf("unset" to 1)
        var succeeded = false
        var error: String? = null
        NextAlarm.answer(
            { throw SecurityException("denied") },
            { succeeded = true; success = it },
            { code, _ -> error = code },
        )
        assertEquals("failed", error)
        assertEquals(false, succeeded)
    }

    @Test
    fun successfulReadIsReported() {
        var got: Map<String, Any>? = null
        var error: String? = null
        NextAlarm.answer({ 1_800_000_000_000L }, { got = it }, { c, _ -> error = c })
        assertEquals(mapOf("at" to 1_800_000_000_000L), got)
        assertNull(error)
    }
}
