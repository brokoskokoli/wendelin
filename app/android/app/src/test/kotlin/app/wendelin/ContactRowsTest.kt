package app.wendelin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Grouping of address-book rows and the plain-number check of the contacts channel. */
class ContactRowsTest {
    private fun phone(id: Long, name: String?, number: String?, label: String? = "Mobil") =
        ContactRows.Row(id, name, ContactRows.Kind.PHONE, number, label)

    private fun mail(id: Long, name: String?, address: String?) =
        ContactRows.Row(id, name, ContactRows.Kind.EMAIL, address, null)

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

    private fun row(kind: ContactRows.Kind, value: String?, label: String? = null) =
        ContactRows.Row(1, "Anna Meier", kind, value, label)

    private val annaRows = listOf(
        row(ContactRows.Kind.PHONE, "030 555-0100", "Arbeit"),
        row(ContactRows.Kind.EMAIL, "anna@example.org"),
        row(ContactRows.Kind.ADDRESS, "Musterstraße 1\n12345 Musterstadt", "Privat"),
        row(ContactRows.Kind.ADDRESS, "Musterstraße 1, 12345 Musterstadt", "Arbeit"),
        row(ContactRows.Kind.ADDRESS, "Beispielweg 2, 54321 Beispielstadt", "Arbeit"),
        row(ContactRows.Kind.BIRTHDAY, "1985-03-14"),
        row(ContactRows.Kind.ORGANIZATION, "Muster GmbH"),
    )

    @Test
    fun withoutFieldsOnlyPhonesAndEmailsAreHandedOut() {
        val anna = ContactRows.merge(annaRows).single()
        assertEquals(setOf("name", "phones", "emails"), anna.keys)
    }

    @Test
    fun addressOnlyHandsOutNothingElse() {
        val anna = ContactRows.merge(annaRows, setOf(ContactRows.Kind.ADDRESS)).single()
        assertEquals(setOf("name", "addresses"), anna.keys)
        // One line per address, identical addresses of a contact appear once.
        assertEquals(
            listOf(
                mapOf("address" to "Musterstraße 1, 12345 Musterstadt", "label" to "Privat"),
                mapOf("address" to "Beispielweg 2, 54321 Beispielstadt", "label" to "Arbeit"),
            ),
            anna["addresses"],
        )
    }

    @Test
    fun birthdayAndOrganizationOnlyWhenStored() {
        val both = setOf(ContactRows.Kind.BIRTHDAY, ContactRows.Kind.ORGANIZATION)
        val anna = ContactRows.merge(annaRows, both).single()
        assertEquals(mapOf("name" to "Anna Meier", "birthday" to "1985-03-14", "organization" to "Muster GmbH"), anna)
        val bare = ContactRows.merge(listOf(phone(2, "Ben", "0170 1")), both).single()
        assertEquals(mapOf<String, Any>("name" to "Ben"), bare)
    }

    @Test
    fun contactWithoutRequestedDataStaysWithAnEmptyList() {
        val ben = ContactRows.merge(listOf(phone(2, "Ben", "0170 1")), setOf(ContactRows.Kind.ADDRESS)).single()
        assertEquals(emptyList<Any>(), ben["addresses"])
    }

    @Test
    fun parseFieldsRefusesUnknownAndEmpty() {
        assertEquals(ContactRows.DEFAULT_FIELDS, ContactRows.parseFields(null))
        assertEquals(setOf(ContactRows.Kind.ADDRESS), ContactRows.parseFields(listOf("address", "address")))
        for (bad in listOf(emptyList(), listOf("note"), listOf("address", "Phone"))) {
            try {
                ContactRows.parseFields(bad)
                throw AssertionError("accepted $bad")
            } catch (e: ArgumentException) {
                assertEquals("argument fields", e.message)
            }
        }
    }
}
