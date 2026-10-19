package app.wendelin

/**
 * Contact rows to channel maps and number checks, without Android types (JVM-testable). Used by
 * [ContactsChannel].
 */
object ContactRows {
    /** One `ContactsContract.Data` row: a phone number or a mail address of a contact. */
    data class Row(
        val contactId: Long,
        val name: String?,
        val isPhone: Boolean,
        val value: String?,
        val label: String?,
    )

    private val NUMBER = Regex("^\\+?[0-9]{3,20}$")

    /** Whether [number] is a plain phone number (digits, optional leading `+`), as Dart sends it. */
    fun validNumber(number: String?): Boolean = number != null && NUMBER.matches(number)

    /**
     * Groups [rows] by contact (order of first appearance) into `{name, phones: [{number, label}],
     * emails}`. Rows without value are skipped, duplicate numbers/addresses of a contact appear once,
     * contacts without any entry are left out.
     */
    fun merge(rows: List<Row>): List<Map<String, Any>> {
        val byId = LinkedHashMap<Long, MutableList<Row>>()
        for (r in rows) {
            if (r.value.isNullOrBlank()) continue
            byId.getOrPut(r.contactId) { mutableListOf() }.add(r)
        }
        return byId.values.mapNotNull { group ->
            val name = group.firstNotNullOfOrNull { it.name?.takeIf(String::isNotBlank) } ?: return@mapNotNull null
            val phones = group.filter { it.isPhone }
                .distinctBy { it.value!!.filter(Char::isDigit) + it.value.startsWith("+") }
                .map { mapOf("number" to it.value!!.trim(), "label" to (it.label ?: "")) }
            val emails = group.filter { !it.isPhone }.map { it.value!!.trim() }.distinct()
            mapOf("name" to name, "phones" to phones, "emails" to emails)
        }
    }
}
