package app.wendelin

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Argument checks of the channels without Android. */
class ChannelArgsTest {
    private fun args(vararg pairs: Pair<String, Any?>) = ChannelArgs.of(mapOf(*pairs))

    @Test
    fun requiredStringMustBePresentAndAString() {
        assertEquals("x", args("id" to "x").requireString("id"))
        for (a in listOf(args(), args("id" to 5), args("id" to null), ChannelArgs.of(null), ChannelArgs.of("text"))) {
            try {
                a.requireString("id")
                fail("expected ArgumentException")
            } catch (e: ArgumentException) {
                assertEquals("id", e.key)
            }
        }
    }

    @Test
    fun numbersComeAsIntOrLong() {
        assertEquals(7L, args("n" to 7).requireLong("n"))
        assertEquals(8_000_000_000L, args("n" to 8_000_000_000L).requireLong("n"))
        try {
            args("n" to "7").requireLong("n")
            fail("a string is no number")
        } catch (e: ArgumentException) {
            assertEquals("n", e.key)
        }
    }

    @Test
    fun booleanIsTrueOnlyForExplicitTrue() {
        assertTrue(args("b" to true).isTrue("b"))
        assertFalse(args("b" to false).isTrue("b"))
        assertFalse(args("b" to "true").isTrue("b"))
        assertFalse(args().isTrue("b"))
    }

    @Test
    fun bytesAndLists() {
        assertArrayEquals(byteArrayOf(1, 2), args("d" to byteArrayOf(1, 2)).requireBytes("d"))
        try {
            args("d" to "text").requireBytes("d")
            fail("a string is no byte array")
        } catch (e: ArgumentException) {
            assertEquals("d", e.key)
        }
        assertEquals(listOf("a", "b"), args("l" to listOf("a", "b")).stringList("l"))
        assertNull(args().stringList("l"))
        assertNull(args("s" to 1).string("s"))
    }
}
