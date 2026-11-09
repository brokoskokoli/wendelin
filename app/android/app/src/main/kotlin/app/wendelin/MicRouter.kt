package app.wendelin

import android.content.Context
import android.content.SharedPreferences
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Handler

/** The route the microphone should take: [info] `null` = system default; [type] is for logs only. */
internal class MicTarget(val key: String?, val info: AudioDeviceInfo?, val type: String) {
    companion object {
        val SYSTEM = MicTarget(null, null, "system")
    }
}

/**
 * Android side of the microphone choice (WP188 part D): reads the choice from
 * [AudioDeviceSelectionStore] (no Flutter engine needed, so it also works after a restart of the
 * service) and the connected inputs from `AudioManager`, and calls the callback of [watch] when the
 * choice or the devices change. The decision itself is [MicRoute]. Never logs an address.
 */
class MicRouter(context: Context) {
    private val app = context.applicationContext
    private val audio = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val store = AudioDeviceSelectionStore(app)
    private var callback: AudioDeviceCallback? = null
    private var prefsListener: SharedPreferences.OnSharedPreferenceChangeListener? = null

    /** The wanted route now: the chosen input if connected, else the system. Errors mean system. */
    internal fun target(): MicTarget = try {
        val infos = audio.getDevices(AudioManager.GET_DEVICES_INPUTS).toList()
        val descs = infos.map { AudioDeviceDesc(it.type, it.productName?.toString() ?: "", it.address, it.isSource, it.isSink) }
        val key = MicRoute.target(store.get(AudioDevicePick.INPUT), descs, OwnCommMode.active)
        val i = if (key == null) -1 else descs.indexOfFirst { AudioDevicePick.keyOf(it) == key }
        if (i < 0) {
            MicTarget.SYSTEM
        } else {
            MicTarget(key, infos[i], AudioDevicePick.typeName(descs[i], AudioDevicePick.INPUT) ?: "other")
        }
    } catch (e: RuntimeException) {
        MicTarget.SYSTEM
    }

    /** The connected Bluetooth headset of the choice (inputs and outputs), for the dialog; errors mean none. */
    internal fun dialogHeadset(): AudioDeviceInfo? = try {
        val infos = audio.getDevices(AudioManager.GET_DEVICES_ALL).toList()
        val descs = infos.map { AudioDeviceDesc(it.type, it.productName?.toString() ?: "", it.address, it.isSource, it.isSink) }
        val hit = DialogBluetooth.connected(store.get(AudioDevicePick.INPUT), descs)
        if (hit == null) null else infos[descs.indexOf(hit)]
    } catch (e: RuntimeException) {
        null
    }

    /**
     * Calls [onChange] (on [handler]'s thread) when an audio device comes or goes and when the app
     * changes the chosen microphone. A preference listener rather than a channel call: it also
     * covers every other writer and needs no link from the UI engine to the service (same process).
     */
    fun watch(handler: Handler, onChange: () -> Unit) {
        unwatch()
        val cb = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) = onChange()
            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) = onChange()
        }
        audio.registerAudioDeviceCallback(cb, handler)
        callback = cb
        val prefs = app.getSharedPreferences(AudioDeviceSelectionStore.PREFS_NAME, Context.MODE_PRIVATE)
        val l = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == AudioDeviceSelectionStore.INPUT_KEY) handler.post(onChange)
        }
        prefs.registerOnSharedPreferenceChangeListener(l)
        prefsListener = l
    }

    /** Stops [watch] (idempotent). */
    fun unwatch() {
        callback?.let { audio.unregisterAudioDeviceCallback(it) }
        callback = null
        prefsListener?.let {
            app.getSharedPreferences(AudioDeviceSelectionStore.PREFS_NAME, Context.MODE_PRIVATE)
                .unregisterOnSharedPreferenceChangeListener(it)
        }
        prefsListener = null
    }
}
