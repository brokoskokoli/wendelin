package app.wendelin

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform side of `AudioTrackPlayback` (app/lib/platform/voice/audio_track_playback.dart, WP188):
 * plays a mono 16 bit clip on an [AudioTrack] (speech of an assistant) on the output the user chose
 * in [AudioDeviceSelectionStore], else on the system route. `play` answers when the playback head
 * reached the end of the clip (not when the last frame was written), `stop` ends it at once (pause,
 * flush, release, no tail). A newer `play` replaces the running one. While a clip runs, devices
 * coming and going set the route anew ([AudioOutputRoute]) without interrupting it. Holds a
 * transient focus that lets others duck, like the audioplayers path. Needs no permission
 * (`setPreferredDevice` and the device callback do not).
 */
class AudioPlaybackChannel(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val store = AudioDeviceSelectionStore(context)
    private val handler = Handler(Looper.getMainLooper())
    private var current: Playing? = null

    private val attributes =
        AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANT)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        current?.end()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val args = ChannelArgs.of(call.arguments)
        try {
            when (call.method) {
                "play" -> play(args.requireBytes("pcm"), args.requireLong("sampleRate").toInt(), result)
                "stop" -> {
                    current?.end()
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

    private fun play(pcm: ByteArray, sampleRate: Int, result: MethodChannel.Result) {
        current?.end()
        if (pcm.size < 2) {
            result.success(null)
            return
        }
        val track = AudioTrack.Builder()
            .setAudioAttributes(attributes)
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
            )
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(pcm.size)
            .build()
        try {
            track.write(pcm, 0, pcm.size)
        } catch (e: Exception) {
            track.release()
            throw e
        }
        val playing = Playing(track, pcm.size / 2, result)
        current = playing
        playing.start()
    }

    /** One running clip. [end] is the only way out and runs once. */
    private inner class Playing(
        private val track: AudioTrack,
        private val frames: Int,
        private val result: MethodChannel.Result,
    ) {
        private var ended = false
        private val progress = PlaybackProgress(frames, STALL_MS, SystemClock.elapsedRealtime())
        private var focus: AudioFocusRequest? = null
        private val devices = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) = route()
            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) = route()
        }
        private val poll = object : Runnable {
            override fun run() {
                if (ended) return
                val state = try {
                    progress.onPoll(track.playbackHeadPosition, SystemClock.elapsedRealtime())
                } catch (e: Exception) {
                    PlaybackState.STALLED
                }
                if (state == PlaybackState.PLAYING) handler.postDelayed(this, POLL_MS) else end()
            }
        }

        fun start() {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(attributes)
                .build()
            // The clip is played even if the focus is refused (as the audioplayers path does).
            if (audio.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) focus = request
            route()
            audio.registerAudioDeviceCallback(devices, handler)
            // The dialog's phone mode starts/ends mid-clip: route again at once, not at the next clip.
            OwnCommMode.listener = { handler.post { route() } }
            track.play()
            handler.postDelayed(poll, POLL_MS)
        }

        /** Sets the output from the stored choice and the devices connected right now. */
        private fun route() {
            if (ended) return
            try {
                val infos = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                val descs = infos.map {
                    AudioDeviceDesc(it.type, it.productName?.toString() ?: "", it.address, it.isSource, it.isSink)
                }
                val index = AudioOutputRoute.deviceIndex(store.get(AudioDevicePick.OUTPUT), descs, OwnCommMode.active)
                // null = system route (device missing or no choice).
                track.setPreferredDevice(index?.let { infos[it] })
            } catch (e: Exception) {
                // A routing error must not end the clip; the system route stays.
            }
        }

        fun end() {
            if (ended) return
            ended = true
            if (current === this) {
                current = null
                OwnCommMode.listener = null
            }
            handler.removeCallbacks(poll)
            audio.unregisterAudioDeviceCallback(devices)
            try {
                track.pause()
                track.flush()
                track.stop()
            } catch (e: IllegalStateException) {
                // Already stopped.
            }
            track.release()
            focus?.let { audio.abandonAudioFocusRequest(it) }
            result.success(null)
        }
    }

    companion object {
        const val CHANNEL = "app.wendelin/audio-playback"
        private const val POLL_MS = 20L
        private const val STALL_MS = 3000L
    }
}
