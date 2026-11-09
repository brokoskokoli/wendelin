package app.wendelin

import android.content.Context

/** Minimal string store (private preferences in the app, a map in tests). */
interface KeyValues {
    fun getString(key: String): String?
    fun putString(key: String, value: String?)
}

/** [KeyValues] over private `SharedPreferences`. */
class PrefsKeyValues(context: Context) : KeyValues {
    private val prefs =
        context.applicationContext.getSharedPreferences(AudioDeviceSelectionStore.PREFS_NAME, Context.MODE_PRIVATE)

    override fun getString(key: String): String? = prefs.getString(key, null)

    override fun putString(key: String, value: String?) {
        prefs.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply()
    }
}

/**
 * The chosen microphone and output as [AudioDeviceEntry] (stable key, type, product name; the name
 * is kept so the UI can show a chosen device that is gone); `null` = system default (WP188).
 * Natively persisted so the wake service can read the microphone choice without a Flutter engine
 * (part D); the app writes it through [AudioDevicesChannel].
 */
class AudioDeviceSelectionStore(private val kv: KeyValues) {
    constructor(context: Context) : this(PrefsKeyValues(context))

    companion object {
        /** Preferences file; the wake service listens to [INPUT_KEY] to follow a changed choice. */
        const val PREFS_NAME = "app.wendelin.audio_devices"
        const val INPUT_KEY = "input.key"
    }

    /** The selection for [direction], `null` for the system default or an unreadable store. */
    fun get(direction: String): AudioDeviceEntry? {
        require(AudioDevicePick.isDirection(direction)) { "direction" }
        return try {
            val key = kv.getString("$direction.key")?.takeIf { it.isNotEmpty() } ?: return null
            AudioDeviceEntry(key, kv.getString("$direction.type") ?: "", kv.getString("$direction.name") ?: "")
        } catch (e: RuntimeException) {
            null
        }
    }

    /** Selects [entry] for [direction]; `null` or an empty key goes back to the system. */
    fun set(direction: String, entry: AudioDeviceEntry?) {
        require(AudioDevicePick.isDirection(direction)) { "direction" }
        val e = entry?.takeIf { it.key.isNotEmpty() }
        kv.putString("$direction.key", e?.key)
        kv.putString("$direction.type", e?.type)
        kv.putString("$direction.name", e?.name)
    }
}
