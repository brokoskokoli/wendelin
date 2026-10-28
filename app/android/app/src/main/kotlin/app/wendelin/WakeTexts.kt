package app.wendelin

import android.content.Context

/**
 * The texts of the wake-word notifications in the app language (WP156). The app sends them with
 * `texts` on the wake channel at every start and language change; they are kept in the private
 * preferences, so a start without Dart (boot, restart by the system) still speaks the language
 * of the last app run. Without stored text the German default stays.
 *
 * `{time}` in [pausedText] and `{reason}` in [ended] are placeholders filled at use.
 */
class WakeTexts(private val stored: (String) -> String?) {
    private fun t(key: String): String = stored(key)?.takeIf { it.isNotBlank() } ?: DEFAULTS.getValue(key)

    val channelDesc get() = t("channelDesc")
    val listeningTitle get() = t("listeningTitle")
    val listeningText get() = t("listeningText")
    val pause get() = t("pause")
    val off get() = t("off")
    val pausedTitle get() = t("pausedTitle")
    val resume get() = t("resume")
    val reenableTitle get() = t("reenableTitle")
    val reenableAction get() = t("reenableAction")
    val noRole get() = t("noRole")
    val gapText get() = t("gapText")
    val gapAction get() = t("gapAction")
    val gapNoSeqText get() = t("gapNoSeqText")
    val gapNoSeqAction get() = t("gapNoSeqAction")

    /** Notification text for the stage 2 [gap] reason (`no_sequences`: enroll again; else model). */
    fun gapTextFor(gap: String): String = if (gap == "no_sequences") gapNoSeqText else gapText

    /** Button label for the stage 2 [gap] reason. */
    fun gapActionFor(gap: String): String = if (gap == "no_sequences") gapNoSeqAction else gapAction

    fun pausedText(time: String) = t("pausedText").replace("{time}", time)

    fun ended(reason: String) = t("ended").replace("{reason}", reason)

    companion object {
        private const val PREFS = "app.wendelin.wake"
        private const val PREFIX = "text."
        private const val MAX_LEN = 400

        /** German fallback, as the notifications spoke before WP156 (now „Hey Wendelin“). */
        val DEFAULTS = mapOf(
            "channelDesc" to "Zeigt, dass Wendelin auf „Hey Wendelin“ hört.",
            "listeningTitle" to "Wendelin hört auf „Hey Wendelin“",
            "listeningText" to "Das Mikrofon ist an. Audio bleibt auf dem Gerät.",
            "pause" to "Pause 1 h",
            "off" to "Aus",
            "pausedTitle" to "Wendelin pausiert",
            "pausedText" to "Bis {time} Uhr, das Mikrofon ist frei.",
            "resume" to "Fortsetzen",
            "reenableTitle" to "Aktivierungswort ist aus",
            "reenableAction" to "Wieder einschalten",
            "noRole" to "Wendelin muss der Assistent sein, damit das Aktivierungswort nach einem Neustart laufen kann.",
            "gapText" to "Aktivierungswort kann nicht geprüft werden – Erkennungsmodell laden",
            "gapAction" to "Modell laden",
            "gapNoSeqText" to "Aktivierungswort kann nicht sicher geprüft werden – bitte neu einlernen",
            "gapNoSeqAction" to "Neu einlernen",
            "ended" to "Das Aktivierungswort wurde beendet ({reason}). Tippe, um es wieder einzuschalten.",
        )

        /** The known, non-blank, not overlong entries of [args] (what the app sent). */
        fun sanitize(args: Map<*, *>?): Map<String, String> = buildMap {
            for (key in DEFAULTS.keys) {
                val v = args?.get(key) as? String
                if (v != null && v.isNotBlank() && v.length <= MAX_LEN) put(key, v)
            }
        }

        fun load(context: Context): WakeTexts {
            val p = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            return WakeTexts { p.getString(PREFIX + it, null) }
        }

        /** Replaces the stored texts by the valid ones of [args]; a missing key falls back to German. */
        fun save(context: Context, args: Map<*, *>?) {
            val ok = sanitize(args)
            val e = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            for (key in DEFAULTS.keys) {
                ok[key]?.let { e.putString(PREFIX + key, it) } ?: e.remove(PREFIX + key)
            }
            e.apply()
        }
    }
}
