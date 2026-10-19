package app.wendelin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Grouping of address-book rows and the plain-number check of the contacts channel. */
class ContactRowsTest {
    private fun phone(id: Long, name: String?, number: String?, label: String? = "Mobil") =
        ContactRows.Row(id, name, true, number, label)

    private fun mail(id: Long, name: String?, address: String?) =
        ContactRows.Row(id, name, false, address, null)

    @Test
    fun groupsRowsByContactInOrderOfAppearance() {
        val merged = ContactRows.merge(
            listOf(
                phone(2, "Berta", "030 1"),
                phone(1, "Anna", "0170 1"),
                mail(2, "Berta", "b@example.org"),
                phone(1, "Anna", "0170 2", "Arbeit"),
            ),
        )
        assertEquals(listOf("Berta", "Anna"), merged.map { it["name"] })
        val anna = merged[1]
        assertEquals(
            listOf(mapOf("number" to "0170 1", "label" to "Mobil"), mapOf("number" to "0170 2", "label" to "Arbeit")),
            anna["phones"],
        )
        assertEquals(listOf("b@example.org"), merged[0]["emails"])
    }

    @Test
    fun dropsEmptyValuesAndContactsWithoutEntries() {
        val merged = ContactRows.merge(listOf(phone(1, "Anna", " "), mail(2, "Berta", null), phone(3, null, "123")))
        assertTrue(merged.isEmpty())
    }

    @Test
    fun sameNumberInDifferentSpellingAppearsOnce() {
        val merged = ContactRows.merge(listOf(phone(1, "Anna", "0170 123"), phone(1, "Anna", "0170-123")))
        assertEquals(1, (merged.single()["phones"] as List<*>).size)
    }

    @Test
    fun plusAndNationalFormStayApart() {
        val merged = ContactRows.merge(listOf(phone(1, "Anna", "+49170123"), phone(1, "Anna", "49170123")))
        assertEquals(2, (merged.single()["phones"] as List<*>).size)
    }

    @Test
    fun onlyPlainNumbersAreValid() {
        assertTrue(ContactRows.validNumber("+491701234567"))
        assertTrue(ContactRows.validNumber("0301234"))
        assertFalse(ContactRows.validNumber(null))
        assertFalse(ContactRows.validNumber("12"))
        assertFalse(ContactRows.validNumber("0170 123"))
        assertFalse(ContactRows.validNumber("0170123;ATD"))
        assertFalse(ContactRows.validNumber("*#06#"))
        assertFalse(ContactRows.validNumber("+" + "1".repeat(21)))
    }

    @Test
    fun unitBecomesNullForTheChannel() {
        assertEquals(null, ContactRows.channelValue(Unit))
        assertEquals(null, ContactRows.channelValue(null))
        assertEquals("x", ContactRows.channelValue("x"))
        assertEquals(emptyList<Any>(), ContactRows.channelValue(emptyList<Any>()))
    }
}
