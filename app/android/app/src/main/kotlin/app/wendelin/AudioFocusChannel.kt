package app.wendelin

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform side of `ChannelAudioFocusPort` (app/lib/platform/channel_audio_focus_port.dart):
 * holds the audio focus for the whole spoken answer (`duck`, other players get quieter) and for
 * the recording (`listen`, other players pause and resume). See [AudioFocusKinds]. Losing the
 * focus is reported to Dart as `focusChanged` ({kind, state: lost|gained}); the recording pauses
 * meanwhile.
 */
class AudioFocusChannel(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val held = HashMap<String, AudioFocusRequest>()
    private val route = SpeechRoute(AndroidRouteAudio(audio))

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        releaseAll(held.keys.toList(), ::release, route)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val args = ChannelArgs.of(call.arguments)
        try {
            when (call.method) {
                "acquire" -> result.success(acquire(args.requireString("kind")))
                "release" -> {
                    release(args.requireString("kind"))
                    result.success(null)
                }
                "enterCommunication" -> result.success(route.enter())
                "audioMode" -> result.success(audio.mode)
                "leaveCommunication" -> {
                    route.leave()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: ArgumentException) {
            result.error("bad_args", "${e.key} fehlt", null)
        } catch (e: Exception) {
            result.error("failed", e.message, null)
        }
    }

    private fun acquire(kind: String): Boolean {
        val gain = AudioFocusKinds.gainFor(kind)
            ?: throw IllegalArgumentException("Unbekannte Art")
        if (held.containsKey(kind)) return true
        val attributes =
            AudioAttributes.Builder()
                .setUsage(
                    if (SpeechRoute.active) AudioAttributes.USAGE_VOICE_COMMUNICATION
                    else AudioAttributes.USAGE_ASSISTANT,
                )
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
        // The answer is spoken anyway; the recording pauses on a loss (Dart side).
        val request =
            AudioFocusRequest.Builder(gain)
                .setAudioAttributes(attributes)
                .setOnAudioFocusChangeListener { change -> onChange(kind, change) }
                .build()
        val granted = audio.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        if (granted) held[kind] = request
        return granted
    }

    private fun onChange(kind: String, change: Int) {
        // A permanent loss ends the request: forget it, so the next acquire asks anew.
        if (AudioFocusKinds.isPermanent(change)) {
            held.remove(kind)?.let { audio.abandonAudioFocusRequest(it) }
        }
        val state = AudioFocusKinds.stateFor(change) ?: return
        channel.invokeMethod("focusChanged", mapOf("kind" to kind, "state" to state))
    }

    private fun release(kind: String) {
        held.remove(kind)?.let { audio.abandonAudioFocusRequest(it) }
    }

    companion object {
        const val CHANNEL = "app.wendelin/audiofocus"
    }
}

/** [RouteAudio] over `AudioManager`. */
class AndroidRouteAudio(private val audio: AudioManager) : RouteAudio {
    override val sdk: Int get() = Build.VERSION.SDK_INT

    override var mode: Int
        get() = audio.mode
        set(value) {
            audio.mode = value
        }

    @Suppress("DEPRECATION")
    override var speakerphoneOn: Boolean
        get() = audio.isSpeakerphoneOn
        set(value) {
            audio.isSpeakerphoneOn = value
        }

    override var communicationDevice: Any?
        get() = if (sdk >= 31) audio.communicationDevice else null
        set(value) {
            if (sdk < 31) return
            if (value is AudioDeviceInfo) audio.setCommunicationDevice(value) else audio.clearCommunicationDevice()
        }

    override fun builtinSpeaker(): Any? =
        if (sdk < 31) null
        else audio.availableCommunicationDevices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }

    // Only a device the call path can really use counts: from API 31 the communication devices,
    // before that the outputs. A plain A2DP speaker is no communication device.
    override fun externalOutputActive(): Boolean =
        (if (sdk >= 31) audio.availableCommunicationDevices
        else audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).toList()).any { it.type in EXTERNAL }

    private companion object {
        val EXTERNAL = setOf(
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_HEARING_AID,
        )
    }
}

/** End of the channel: gives back every focus, then the own part of the call path (not the others'). */
internal fun releaseAll(kinds: List<String>, release: (String) -> Unit, route: SpeechRoute) {
    for (kind in kinds) release(kind)
    route.release()
}
