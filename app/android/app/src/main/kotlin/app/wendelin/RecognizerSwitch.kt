package app.wendelin

import android.app.role.RoleManager
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings

/**
 * Keeps [WendelinRecognitionService] enabled only while Wendelin holds the assistant role and
 * the user offers it to other apps (Einstellungen → Assistent, „Als Spracherkennung für andere
 * Apps anbieten“, on by default).
 *
 * The component is disabled in the manifest, so installing the app never makes it the system
 * speech recognizer. It is switched on here when Wendelin is the assistant
 * ([WendelinVoiceInteractionService.onReady], app start), off again when it is not.
 *
 * The same preferences hold the speech settings the app mirrors for the service
 * ([RecognizerConfig]): the recognizer engine has no database access (ADR 0008).
 */
object RecognizerSwitch {
    private const val PREFS = "app.wendelin.recognizer"
    private const val KEY_OFFERED = "offered"

    fun sync(context: Context, holdsRole: Boolean = holdsAssistantRole(context)) {
        val component = ComponentName(context, WendelinRecognitionService::class.java)
        val wanted = stateFor(holdsRole && isOffered(context))
        val pm = context.packageManager
        if (pm.getComponentEnabledSetting(component) == wanted) return
        pm.setComponentEnabledSetting(component, wanted, PackageManager.DONT_KILL_APP)
    }

    /** Component state of the service: enabled only while it is wanted (role held and offered). */
    fun stateFor(wanted: Boolean): Int =
        if (wanted) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT
        }

    /** Whether the service may answer right now (role held and offered). */
    fun isActive(context: Context): Boolean = isOffered(context) && holdsAssistantRole(context)

    fun isOffered(context: Context): Boolean = prefs(context).getBoolean(KEY_OFFERED, true)

    fun setOffered(context: Context, offered: Boolean) {
        prefs(context).edit().putBoolean(KEY_OFFERED, offered).apply()
        sync(context)
    }

    fun holdsAssistantRole(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return context.getSystemService(RoleManager::class.java)
                ?.isRoleHeld(RoleManager.ROLE_ASSISTANT) == true
        }
        val current = Settings.Secure.getString(context.contentResolver, "assistant") ?: return false
        return ComponentName.unflattenFromString(current)?.packageName == context.packageName
    }

    internal fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}

/**
 * Speech settings of the app (Einstellungen → Sprache) for the recognizer engine: Whisper
 * model, language (`""` = detect), Silero threshold and minimum speech duration. Written by the
 * app on every change (`setRecognizerConfig` on the assistant channel).
 */
data class RecognizerConfig(
    val model: String = "whisper-small",
    val language: String = "",
    val vadThreshold: Double = 0.5,
    val minSpeechMs: Int = 200,
) {
    fun toArgs(): Map<String, Any> = mapOf(
        "model" to model,
        "sttLanguage" to language,
        "vadThreshold" to vadThreshold,
        "minSpeechMs" to minSpeechMs,
    )

    fun save(context: Context) {
        RecognizerSwitch.prefs(context).edit()
            .putString("model", model)
            .putString("language", language)
            .putFloat("vadThreshold", vadThreshold.toFloat())
            .putInt("minSpeechMs", minSpeechMs)
            .apply()
    }

    companion object {
        fun load(context: Context): RecognizerConfig {
            val p = RecognizerSwitch.prefs(context)
            val d = RecognizerConfig()
            return RecognizerConfig(
                model = p.getString("model", null) ?: d.model,
                language = p.getString("language", null) ?: d.language,
                vadThreshold = p.getFloat("vadThreshold", d.vadThreshold.toFloat()).toDouble(),
                minSpeechMs = p.getInt("minSpeechMs", d.minSpeechMs),
            )
        }

        /** Reads the channel arguments; missing or invalid values keep the defaults. */
        fun fromArgs(args: Map<*, *>?): RecognizerConfig {
            val d = RecognizerConfig()
            val model = (args?.get("model") as? String)?.takeIf { it.startsWith("whisper-") }
            val language = (args?.get("language") as? String)
                ?.takeIf { it.isEmpty() || it in setOf("de", "fr", "en") }
            val threshold = (args?.get("vadThreshold") as? Number)?.toDouble()
                ?.takeIf { it > 0 && it < 1 }
            val minSpeech = (args?.get("minSpeechMs") as? Number)?.toInt()
                ?.takeIf { it in 50..1000 }
            return RecognizerConfig(
                model = model ?: d.model,
                language = language ?: d.language,
                vadThreshold = threshold ?: d.vadThreshold,
                minSpeechMs = minSpeech ?: d.minSpeechMs,
            )
        }
    }
}
