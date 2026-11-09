package app.wendelin

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform side of `ChannelAudioDevicesPort` (app/lib/platform/voice/audio_devices.dart, WP188):
 * lists the microphones and outputs (`devices`), keeps the choice of each direction
 * (`selection`, `setSelection`, stored in [AudioDeviceSelectionStore]) and reports coming and
 * going devices as `devicesChanged`. Needs no permission. Never sends or logs an address.
 */
class AudioDevicesChannel(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val store = AudioDeviceSelectionStore(context)
    private val callback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) = changed()
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) = changed()
    }

    init {
        channel.setMethodCallHandler(this)
        audio.registerAudioDeviceCallback(callback, Handler(Looper.getMainLooper()))
    }

    fun dispose() {
        audio.unregisterAudioDeviceCallback(callback)
        channel.setMethodCallHandler(null)
    }

    private fun changed() = channel.invokeMethod("devicesChanged", null)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val args = ChannelArgs.of(call.arguments)
        try {
            when (call.method) {
                "devices" -> result.success(devices())
                "selection" -> result.success(
                    mapOf(
                        AudioDevicePick.INPUT to store.get(AudioDevicePick.INPUT)?.toMap(),
                        AudioDevicePick.OUTPUT to store.get(AudioDevicePick.OUTPUT)?.toMap(),
                    ),
                )
                // key null = system default; type and name are kept to show a missing device.
                "setSelection" -> {
                    val key = args.string("key")
                    store.set(
                        args.requireString("direction"),
                        key?.let { AudioDeviceEntry(it, args.string("type") ?: "", args.string("name") ?: "") },
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: ArgumentException) {
            result.error("bad_args", "${e.key} fehlt", null)
        } catch (e: IllegalArgumentException) {
            result.error("bad_args", "Unbekannte Richtung", null)
        } catch (e: Exception) {
            result.error("failed", e.message, null)
        }
    }

    private fun devices(): Map<String, List<Map<String, String>>> {
        val all = audio.getDevices(AudioManager.GET_DEVICES_ALL).map {
            AudioDeviceDesc(it.type, it.productName?.toString() ?: "", it.address, it.isSource, it.isSink)
        }
        fun list(direction: String) = AudioDevicePick.entries(all, direction).map { it.toMap() }
        return mapOf(
            AudioDevicePick.INPUT to list(AudioDevicePick.INPUT),
            AudioDevicePick.OUTPUT to list(AudioDevicePick.OUTPUT),
        )
    }

    private fun AudioDeviceEntry.toMap() = mapOf("key" to key, "type" to type, "name" to name)

    companion object {
        const val CHANNEL = "app.wendelin/audio-devices"
    }
}
