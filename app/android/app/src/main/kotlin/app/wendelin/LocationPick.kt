package app.wendelin

/** What the channel needs to know about one last-known fix (no Android types). */
data class FixInfo(val provider: String, val timeMs: Long, val accuracyM: Float?)

/**
 * Logic of the location channel without Android types, so it runs on the JVM: which cached fix is
 * good enough, the place name from geocoder fields, and which intents the launcher accepts.
 * Coordinates never appear in texts built here.
 */
object LocationPick {
    /** Cached fixes older than this are not used; a fresh one is requested instead. */
    const val MAX_AGE_MS = 120_000L

    /**
     * Index of the best fix that is at most [maxAgeMs] old (not from the future): the smallest
     * accuracy value wins (unknown counts as worst), then the newest. `null` if none qualifies.
     */
    fun pick(fixes: List<FixInfo>, nowMs: Long, maxAgeMs: Long = MAX_AGE_MS): Int? =
        fixes.withIndex()
            .filter { (_, f) -> f.timeMs <= nowMs && nowMs - f.timeMs <= maxAgeMs }
            .sortedWith(
                compareBy<IndexedValue<FixInfo>> { it.value.accuracyM ?: Float.MAX_VALUE }
                    .thenByDescending { it.value.timeMs },
            )
            .firstOrNull()?.index

    /**
     * Readable place from geocoder fields: district and town (no street, no number), without
     * repeats; falls back to the region. `null` if the geocoder knows none of them.
     */
    fun placeName(subLocality: String?, locality: String?, adminArea: String?): String? {
        val parts = listOf(subLocality, locality ?: adminArea)
            .mapNotNull { it?.trim()?.takeIf(String::isNotEmpty) }
            .distinct()
        return parts.takeIf { it.isNotEmpty() }?.joinToString(", ")
    }

    private const val GOOGLE_MAPS = "com.google.android.apps.maps"
    private const val WAZE = "com.waze"

    /**
     * Whether the launcher may start this intent: only map schemes (`geo:`, `google.navigation:`,
     * Google Maps web links, Waze links `https://waze.com/ul`) and only the matching package or
     * none, so a tool argument cannot open arbitrary apps or links. A Waze link needs the Waze
     * package, a Google Maps link and `google.navigation:` the Google Maps package or none.
     */
    fun isAllowedLaunch(scheme: String?, host: String?, path: String?, pkg: String?): Boolean {
        if (scheme == "https" && host == "waze.com") return path == "/ul" && pkg == WAZE
        if (pkg != null && pkg != GOOGLE_MAPS) return false
        return when (scheme) {
            "geo", "google.navigation" -> true
            "https" -> host == "www.google.com" && path != null && path.startsWith("/maps/")
            else -> false
        }
    }
}
