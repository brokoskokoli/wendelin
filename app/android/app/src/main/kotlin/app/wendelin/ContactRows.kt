package app.wendelin

/**
 * Contact rows to channel maps and number checks, without Android types (JVM-testable). Used by
 * [ContactsChannel].
 */
object ContactRows {
    /** What `contacts__find` may ask for (`fields`); the wire names are those of the Dart enum. */
    enum class Kind(val wire: String, val mime: String) {
        PHONE("phone", "vnd.android.cursor.item/phone_v2"),
        EMAIL("email", "vnd.android.cursor.item/email_v2"),
        ADDRESS("address", "vnd.android.cursor.item/postal-address_v2"),
        BIRTHDAY("birthday", "vnd.android.cursor.item/contact_event"),
        ORGANIZATION("organization", "vnd.android.cursor.item/organization"),
    }

    /** Data that is loaded only for the hits of a search (`details`), never for the whole book. */
    val EXTRA_FIELDS: Set<Kind> = setOf(Kind.ADDRESS, Kind.BIRTHDAY, Kind.ORGANIZATION)

    /** Marks a row of a presence query: the contact has such data, its content was not read. */
    const val PRESENT = "\u0001"

    /** Most contact ids one `details` call takes (stays far below SQLite's variable limit). */
    const val MAX_IDS = 100

    // Column names of ContactsContract.Data (ContactRowsTest compares them with the constants).
    const val COL_CONTACT_ID = "contact_id"
    const val COL_NAME = "display_name"
    const val COL_MIME = "mimetype"
    const val COL_DATA1 = "data1"
    const val COL_DATA2 = "data2"
    const val COL_DATA3 = "data3"

    /** Event type `TYPE_BIRTHDAY` of `CommonDataKinds.Event`. */
    const val EVENT_BIRTHDAY = "3"

    /** Columns of a query that reads content (the order is the one [ContactsChannel] reads). */
    val DATA_PROJECTION = arrayOf(COL_CONTACT_ID, COL_NAME, COL_MIME, COL_DATA1, COL_DATA2, COL_DATA3)

    /** Columns of a presence query: no content column, so nothing of it is read. */
    val PRESENCE_PROJECTION = arrayOf(COL_CONTACT_ID, COL_NAME, COL_MIME)

    /**
     * `WHERE` clause and arguments for the rows of [kinds] (birthday: event of type birthday only).
     * [nonEmpty] keeps only rows with content (presence queries, mirroring that [merge] skips empty
     * rows); [ids] restricts to those contacts (`details`).
     */
    fun selection(
        kinds: Set<Kind>,
        ids: List<Long>? = null,
        nonEmpty: Boolean = false,
    ): Pair<String, Array<String>> {
        if (kinds.isEmpty()) throw ArgumentException("fields")
        val parts = mutableListOf<String>()
        val args = mutableListOf<String>()
        for (k in Kind.values()) {
            if (k !in kinds) continue
            if (k == Kind.BIRTHDAY) {
                parts.add("($COL_MIME = ? AND $COL_DATA2 = ?)")
                args.add(k.mime)
                args.add(EVENT_BIRTHDAY)
            } else {
                parts.add("$COL_MIME = ?")
                args.add(k.mime)
            }
        }
        var sql = "(" + parts.joinToString(" OR ") + ")"
        if (nonEmpty) sql += " AND $COL_DATA1 IS NOT NULL AND $COL_DATA1 != ''"
        if (ids != null) {
            if (ids.isEmpty() || ids.size > MAX_IDS) throw ArgumentException("ids")
            sql += " AND $COL_CONTACT_ID IN (${ids.joinToString(",") { "?" }})"
            args.addAll(ids.map { it.toString() })
        }
        return sql to args.toTypedArray()
    }

    /** The contact ids of a `details` call; non-numeric entries are refused. */
    fun parseIds(wire: List<String>?): List<Long> {
        if (wire == null || wire.isEmpty() || wire.size > MAX_IDS) throw ArgumentException("ids")
        return wire.map { it.toLongOrNull() ?: throw ArgumentException("ids") }.distinct()
    }

    /** Fields of a `details` call: only [EXTRA_FIELDS], at least one. */
    fun parseDetailFields(wire: List<String>?): Set<Kind> {
        val fields = parseFields(wire)
        if (fields.none { it in EXTRA_FIELDS }) throw ArgumentException("fields")
        return fields.filter { it in EXTRA_FIELDS }.toSet()
    }

    /**
     * The search index for `all`: contacts with phone or mail rows ([dataRows]) plus, for requested
     * extra fields, those with such data ([presenceRows], content not read), sorted by name; only
     * phone and mail of [fields] are handed out, each entry carries the opaque `id` for `details`.
     */
    fun index(dataRows: List<Row>, presenceRows: List<Row>, fields: Set<Kind>): List<Map<String, Any>> {
        val sorted = (dataRows + presenceRows).sortedBy { it.name?.lowercase() ?: "" }
        return merge(sorted, fields.filter { it in DEFAULT_FIELDS }.toSet(), withId = true)
    }

    /** Without a `fields` request: phone numbers and mail addresses, as always. */
    val DEFAULT_FIELDS: Set<Kind> = setOf(Kind.PHONE, Kind.EMAIL)

    /** One `ContactsContract.Data` row of a contact: [kind] tells what [value] is. */
    data class Row(
        val contactId: Long,
        val name: String?,
        val kind: Kind,
        val value: String?,
        val label: String?,
    )

    /**
     * The requested fields: `null` (absent) means [DEFAULT_FIELDS]; an empty list or an unknown name
     * is refused ([ArgumentException]) instead of being ignored.
     */
    fun parseFields(wire: List<String>?): Set<Kind> {
        if (wire == null) return DEFAULT_FIELDS
        if (wire.isEmpty()) throw ArgumentException("fields")
        return wire.map { w -> Kind.values().firstOrNull { it.wire == w } ?: throw ArgumentException("fields") }
            .toSet()
    }

    private val NUMBER = Regex("^\\+?[0-9]{3,20}$")

    /**
     * The value handed to `Result.success`: Kotlin's `Unit` (a block without a result, e.g. sending
     * an SMS) is not encodable by the standard message codec and becomes `null`.
     */
    fun channelValue(value: Any?): Any? = if (value is Unit) null else value

    /** Whether [number] is a plain phone number (digits, optional leading `+`), as Dart sends it. */
    fun validNumber(number: String?): Boolean = number != null && NUMBER.matches(number)

    /**
     * Groups [rows] by contact (order of first appearance) into `{name, ...}` with exactly the
     * [fields] asked for: `phones: [{number, label}]`, `emails`, `addresses: [{address, label}]`
     * (lists are present even if empty; with [withId] also the opaque `id`), `birthday` and `organization` (only if stored). Rows of other
     * kinds only keep a contact in the result and are not handed out. Rows without value are skipped,
     * duplicates of a contact appear once, contacts without any row are left out.
     */
    fun merge(
        rows: List<Row>,
        fields: Set<Kind> = DEFAULT_FIELDS,
        withId: Boolean = false,
    ): List<Map<String, Any>> {
        val byId = LinkedHashMap<Long, MutableList<Row>>()
        for (r in rows) {
            if (r.value.isNullOrBlank()) continue
            byId.getOrPut(r.contactId) { mutableListOf() }.add(r)
        }
        return byId.values.mapNotNull { group ->
            val name = group.firstNotNullOfOrNull { it.name?.takeIf(String::isNotBlank) } ?: return@mapNotNull null
            val out = linkedMapOf<String, Any>("name" to name)
            if (withId) out["id"] = group.first().contactId.toString()
            fun of(kind: Kind) = group.filter { it.kind == kind }
            if (Kind.PHONE in fields) {
                out["phones"] = of(Kind.PHONE)
                    .distinctBy { it.value!!.filter(Char::isDigit) + it.value.startsWith("+") }
                    .map { mapOf("number" to it.value!!.trim(), "label" to (it.label ?: "")) }
            }
            if (Kind.EMAIL in fields) out["emails"] = of(Kind.EMAIL).map { it.value!!.trim() }.distinct()
            if (Kind.ADDRESS in fields) {
                out["addresses"] = of(Kind.ADDRESS)
                    .map { it.copy(value = oneLine(it.value!!)) }
                    .distinctBy { it.value }
                    .map { mapOf("address" to it.value!!, "label" to (it.label ?: "")) }
            }
            if (Kind.BIRTHDAY in fields) of(Kind.BIRTHDAY).firstOrNull()?.let { out["birthday"] = it.value!!.trim() }
            if (Kind.ORGANIZATION in fields) {
                of(Kind.ORGANIZATION).firstOrNull()?.let { out["organization"] = it.value!!.trim() }
            }
            out
        }
    }

    private fun oneLine(address: String): String = address.trim().replace(Regex("\\s*\\n\\s*"), ", ")
}
