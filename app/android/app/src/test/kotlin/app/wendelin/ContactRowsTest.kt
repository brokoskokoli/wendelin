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

    // --- WP164 R1b: selection and index (what is read, and for whom) ---

    private val extras = setOf(ContactRows.Kind.ADDRESS, ContactRows.Kind.BIRTHDAY, ContactRows.Kind.ORGANIZATION)

    @Test
    fun mimeTypesAndColumnsAreThoseOfAndroid() {
        assertEquals(android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE, ContactRows.Kind.PHONE.mime)
        assertEquals(android.provider.ContactsContract.CommonDataKinds.Email.CONTENT_ITEM_TYPE, ContactRows.Kind.EMAIL.mime)
        assertEquals(android.provider.ContactsContract.CommonDataKinds.StructuredPostal.CONTENT_ITEM_TYPE, ContactRows.Kind.ADDRESS.mime)
        assertEquals(android.provider.ContactsContract.CommonDataKinds.Event.CONTENT_ITEM_TYPE, ContactRows.Kind.BIRTHDAY.mime)
        assertEquals(android.provider.ContactsContract.CommonDataKinds.Organization.CONTENT_ITEM_TYPE, ContactRows.Kind.ORGANIZATION.mime)
        assertEquals(android.provider.ContactsContract.CommonDataKinds.Event.TYPE_BIRTHDAY.toString(), ContactRows.EVENT_BIRTHDAY)
        assertEquals(android.provider.ContactsContract.Data.MIMETYPE, ContactRows.COL_MIME)
        assertEquals(android.provider.ContactsContract.Data.CONTACT_ID, ContactRows.COL_CONTACT_ID)
        assertEquals(android.provider.ContactsContract.Data.DISPLAY_NAME, ContactRows.COL_NAME)
        assertEquals(android.provider.ContactsContract.Data.DATA1, ContactRows.COL_DATA1)
        assertEquals(android.provider.ContactsContract.Data.DATA2, ContactRows.COL_DATA2)
        assertEquals(android.provider.ContactsContract.Data.DATA3, ContactRows.COL_DATA3)
    }

    @Test
    fun selectionLoadsOnlyTheMimeTypesOfTheKindsAsked() {
        val (sql, args) = ContactRows.selection(ContactRows.DEFAULT_FIELDS)
        assertEquals("(mimetype = ? OR mimetype = ?)", sql)
        assertEquals(listOf(ContactRows.Kind.PHONE.mime, ContactRows.Kind.EMAIL.mime), args.toList())
        for (k in listOf(ContactRows.Kind.ADDRESS, ContactRows.Kind.BIRTHDAY, ContactRows.Kind.ORGANIZATION)) {
            assertTrue("$k loaded unasked", k.mime !in args)
        }
    }

    @Test
    fun selectionOfExtrasAndBirthdayOnlyAsEventOfTypeBirthday() {
        val (sql, args) = ContactRows.selection(extras)
        assertEquals(
            "(mimetype = ? OR (mimetype = ? AND data2 = ?) OR mimetype = ?)",
            sql,
        )
        assertEquals(
            listOf(ContactRows.Kind.ADDRESS.mime, ContactRows.Kind.BIRTHDAY.mime, "3", ContactRows.Kind.ORGANIZATION.mime),
            args.toList(),
        )
        assertEquals(setOf(ContactRows.Kind.PHONE.mime), ContactRows.selection(setOf(ContactRows.Kind.PHONE)).second.toSet())
    }

    @Test
    fun selectionWithIdsIsRestrictedToThem() {
        val (sql, args) = ContactRows.selection(setOf(ContactRows.Kind.ADDRESS), listOf(7L, 9L))
        assertEquals("(mimetype = ?) AND contact_id IN (?,?)", sql)
        assertEquals(listOf(ContactRows.Kind.ADDRESS.mime, "7", "9"), args.toList())
        assertEquals(sql.count { it == '?' }, args.size)
    }

    @Test
    fun selectionRefusesEmptyKindsAndBadIdLists() {
        for (bad in listOf<() -> Any>(
            { ContactRows.selection(emptySet()) },
            { ContactRows.selection(extras, emptyList()) },
            { ContactRows.selection(extras, List(ContactRows.MAX_IDS + 1) { it.toLong() }) },
        )) {
            try {
                bad()
                throw AssertionError("accepted")
            } catch (e: ArgumentException) {
                // refused
            }
        }
    }

    @Test
    fun presenceSelectionSkipsEmptyContentWithoutReadingIt() {
        val (sql, _) = ContactRows.selection(setOf(ContactRows.Kind.ADDRESS), nonEmpty = true)
        assertEquals("(mimetype = ?) AND data1 IS NOT NULL AND data1 != ''", sql)
        assertTrue(ContactRows.PRESENCE_PROJECTION.none { it.startsWith("data") })
        assertTrue(ContactRows.DATA_PROJECTION.any { it == "data1" })
    }

    @Test
    fun parseIdsAndDetailFields() {
        assertEquals(listOf(1L, 2L), ContactRows.parseIds(listOf("1", "2", "1")))
        for (bad in listOf(null, emptyList(), listOf("x"), listOf("1", "")) ) {
            try {
                ContactRows.parseIds(bad)
                throw AssertionError("accepted $bad")
            } catch (e: ArgumentException) {
                assertEquals("argument ids", e.message)
            }
        }
        assertEquals(setOf(ContactRows.Kind.ADDRESS), ContactRows.parseDetailFields(listOf("address", "phone")))
        for (bad in listOf(null, listOf("phone"), listOf("email", "phone"), emptyList())) {
            try {
                ContactRows.parseDetailFields(bad)
                throw AssertionError("accepted $bad")
            } catch (e: ArgumentException) {
                assertEquals("argument fields", e.message)
            }
        }
    }

    @Test
    fun indexKeepsAddressOnlyContactsFindableAndHandsOutNoContent() {
        val data = listOf(phone(1, "Berta", "0170 1"))
        val presence = listOf(
            ContactRows.Row(2, "Anna", ContactRows.Kind.ADDRESS, ContactRows.PRESENT, null),
            ContactRows.Row(1, "Berta", ContactRows.Kind.ADDRESS, ContactRows.PRESENT, null),
        )
        val out = ContactRows.index(data, presence, setOf(ContactRows.Kind.ADDRESS))
        assertEquals(listOf("Anna", "Berta"), out.map { it["name"] })
        assertEquals(listOf("2", "1"), out.map { it["id"] })
        for (c in out) assertEquals(setOf("name", "id"), c.keys)
        assertTrue(out.toString(), !out.toString().contains(ContactRows.PRESENT))
    }

    @Test
    fun indexWithPhoneAndAddressHandsOutPhonesOnly() {
        val out = ContactRows.index(
            listOf(phone(1, "Anna", "0170 1")),
            listOf(ContactRows.Row(1, "Anna", ContactRows.Kind.ADDRESS, ContactRows.PRESENT, null)),
            setOf(ContactRows.Kind.PHONE, ContactRows.Kind.ADDRESS),
        ).single()
        assertEquals(setOf("name", "id", "phones"), out.keys)
    }

    @Test
    fun mergeWithoutIdHasNoIdAndDetailsRowsGetOne() {
        assertTrue("id" !in ContactRows.merge(annaRows).single())
        val d = ContactRows.merge(annaRows, setOf(ContactRows.Kind.ORGANIZATION), withId = true).single()
        assertEquals(mapOf("name" to "Anna Meier", "id" to "1", "organization" to "Muster GmbH"), d)
    }
}
