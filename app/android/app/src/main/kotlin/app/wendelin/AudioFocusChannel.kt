package app.wendelin

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
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

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        for (kind in held.keys.toList()) release(kind)
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
                .setUsage(AudioAttributes.USAGE_ASSISTANT)
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
