package app.wendelin

import android.content.Context
import android.content.SharedPreferences

/**
 * The wake-word settings in private preferences. The app writes them on every change
 * (`configure` on the wake channel); [WendelinVoiceInteractionService] and [WakeWordService]
 * read them without a Flutter engine or database.
 */
object WakeSettingsStore {
    private const val PREFS = "app.wendelin.wake"

    fun load(context: Context): WakeSettings {
        val p = prefs(context)
        return WakeSettings(
            enabled = p.getBoolean("enabled", false),
            mode = WakeMode.parse(p.getString("mode", null)),
            verify = p.getBoolean("verify", true),
            detector = p.getString("detector", null)?.takeIf { it in DETECTORS } ?: "auto",
            pausedUntilMs = p.getLong("pausedUntil", 0L),
            offByUser = p.getBoolean("offByUser", false),
            devMode = p.getBoolean("devMode", false),
        )
    }

    fun save(context: Context, s: WakeSettings) {
        prefs(context).edit()
            .putBoolean("enabled", s.enabled)
            .putString("mode", s.mode.key)
            .putBoolean("verify", s.verify)
            .putString("detector", s.detector)
            .putLong("pausedUntil", s.pausedUntilMs)
            .putBoolean("offByUser", s.offByUser)
            .putBoolean("devMode", s.devMode)
            .apply()
    }

    /** Stores the developer mode only (WP148); a read error counts as off. */
    fun setDevMode(context: Context, on: Boolean) {
        prefs(context).edit().putBoolean("devMode", on).apply()
    }

    /** Last stop reason for the status line of the settings page. */
    fun setLastStop(context: Context, reason: String) {
        prefs(context).edit().putString("lastStop", reason).apply()
    }

    fun lastStop(context: Context): String? = prefs(context).getString("lastStop", null)

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
