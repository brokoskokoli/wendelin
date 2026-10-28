package app.wendelin

/**
 * Contact rows to channel maps and number checks, without Android types (JVM-testable). Used by
 * [ContactsChannel].
 */
object ContactRows {
    /** What `contacts__find` may ask for (`fields`); the wire names are those of the Dart enum. */
    enum class Kind(val wire: String) {
        PHONE("phone"),
        EMAIL("email"),
        ADDRESS("address"),
        BIRTHDAY("birthday"),
        ORGANIZATION("organization"),
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
     * (lists are present even if empty), `birthday` and `organization` (only if stored). Rows of other
     * kinds only keep a contact in the result and are not handed out. Rows without value are skipped,
     * duplicates of a contact appear once, contacts without any row are left out.
     */
    fun merge(rows: List<Row>, fields: Set<Kind> = DEFAULT_FIELDS): List<Map<String, Any>> {
        val byId = LinkedHashMap<Long, MutableList<Row>>()
        for (r in rows) {
            if (r.value.isNullOrBlank()) continue
            byId.getOrPut(r.contactId) { mutableListOf() }.add(r)
        }
        return byId.values.mapNotNull { group ->
            val name = group.firstNotNullOfOrNull { it.name?.takeIf(String::isNotBlank) } ?: return@mapNotNull null
            val out = linkedMapOf<String, Any>("name" to name)
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
