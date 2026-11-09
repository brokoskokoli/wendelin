package app.wendelin

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.util.Log
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.log10
import kotlin.math.sqrt

/**
 * Audio for one recognition request: 16 kHz mono PCM16 in chunks of [CHUNK_SAMPLES], delivered
 * on a background thread. Nothing is written anywhere; chunks only go to the recognizer engine.
 */
interface RecognizerAudioSource {
    /** Starts delivering; [onChunk] gets little-endian PCM16, [onError] ends the source. */
    fun start(onChunk: (ByteArray) -> Unit, onError: (Throwable) -> Unit)

    /** Stops delivering (idempotent). */
    fun stop()

    companion object {
        const val SAMPLE_RATE = 16000

        /** 100 ms per chunk: ten channel calls and level updates per second. */
        const val CHUNK_SAMPLES = 1600

        /**
         * Level for `onRmsChanged`: dBFS (−60 … 0) mapped to the usual range of Android
         * recognizers (about −2 … 10).
         */
        fun rmsDb(chunk: ByteArray): Float {
            val samples = chunk.size / 2
            if (samples == 0) return -2f
            val buf = ByteBuffer.wrap(chunk).order(ByteOrder.LITTLE_ENDIAN)
            var sum = 0.0
            for (i in 0 until samples) {
                val s = buf.getShort(i * 2) / 32768.0
                sum += s * s
            }
            val rms = sqrt(sum / samples)
            val dbfs = if (rms <= 1e-6) -60.0 else (20 * log10(rms)).coerceIn(-60.0, 0.0)
            return (-2 + (dbfs + 60) / 60 * 12).toFloat()
        }
    }
}

/**
 * The microphone (`AudioRecord`, source `VOICE_RECOGNITION`), attributed to the calling app.
 *
 * With a [router] (the wake service, WP188) the chosen microphone is preferred, and [reroute]
 * follows device changes while recording through [SwitchingReader]. Without one (the recognition
 * service) it is the plain system route, exactly as before.
 */
class MicAudioSource(private val context: Context, private val router: MicRouter? = null) : RecognizerAudioSource {
    private val state = ReadState()
    private var thread: Thread? = null
    @Volatile private var reader: SwitchingReader? = null
    private val routing = java.util.concurrent.Executors.newSingleThreadExecutor { r -> Thread(r, "wendelin-mic-route") }

    /** Audio sessions of the running recordings (empty before the start): tell them from foreign ones. */
    val sessionIds: Set<Int> get() = reader?.sessionIds ?: emptySet()

    @SuppressLint("MissingPermission") // Checked by the service before.
    override fun start(onChunk: (ByteArray) -> Unit, onError: (Throwable) -> Unit) {
        val target = router?.target() ?: MicTarget.SYSTEM
        val first = try {
            openTrack(target)
        } catch (e: RuntimeException) {
            // The chosen device did not open: the system route, as if nothing was chosen.
            if (target.info == null) throw e
            VoiceLog.i("wake-mic-route fallback=system from=${target.type}")
            openTrack(MicTarget.SYSTEM)
        }
        val switching = SwitchingReader(first, onEvent = { VoiceLog.i("wake-mic-route $it") })
        reader = switching
        state.begin()
        thread = Thread({
            try {
                readChunks(
                    reader = switching,
                    chunkBytes = RecognizerAudioSource.CHUNK_SAMPLES * 2,
                    running = { state.running },
                    flushOnStop = { state.flushOnStop },
                    onChunk = onChunk,
                )
            } catch (e: Throwable) {
                if (state.running) onError(e)
            } finally {
                switching.releaseAll()
            }
        }, "wendelin-recognizer-mic").also { it.start() }
    }

    /** Builds and starts one `AudioRecord`, on [target]'s device if it has one (`setPreferredDevice`). */
    @SuppressLint("MissingPermission")
    private fun openTrack(target: MicTarget): MicTrack {
        val minBuffer = AudioRecord.getMinBufferSize(
            RecognizerAudioSource.SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val format = AudioFormat.Builder()
            .setSampleRate(RecognizerAudioSource.SAMPLE_RATE)
            .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .build()
        val builder = AudioRecord.Builder()
            .setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
            .setAudioFormat(format)
            .setBufferSizeInBytes(maxOf(minBuffer, RecognizerAudioSource.CHUNK_SAMPLES * 4))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) builder.setContext(context)
        val record = builder.build()
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            throw IllegalStateException("AudioRecord not initialized")
        }
        if (target.info != null && !record.setPreferredDevice(target.info)) {
            record.release()
            throw IllegalStateException("preferred device refused")
        }
        record.startRecording()
        return RecordTrack(record, target.key)
    }

    /**
     * Follows a change of the choice or of the connected devices (any thread): if the wanted route
     * differs from the running one, a second recording is opened on it and takes over when it
     * delivers ([SwitchingReader]); the running one goes on until then. Same route: nothing happens.
     */
    fun reroute() {
        val r = router ?: return
        if (reader == null) return
        try {
            routing.execute {
                try {
                    val target = r.target()
                    val live = reader ?: return@execute
                    when (MicRoute.decide(live.activeKey, live.hasPending, live.pendingKey, target.key)) {
                        MicRoute.Action.KEEP -> Unit
                        MicRoute.Action.CANCEL_PENDING -> live.cancelPending()
                        MicRoute.Action.SWITCH -> {
                            VoiceLog.i("wake-mic-route to=${target.type}")
                            val track = openTrack(target)
                            // Stopped meanwhile: do not leave a recording behind.
                            if (state.running && reader === live) live.offer(track) else track.release()
                        }
                    }
                } catch (e: RuntimeException) {
                    VoiceLog.i("wake-mic-route failed=${e.javaClass.simpleName}")
                }
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            // Stopped.
        }
    }

    override fun stop() {
        state.stop()
        thread = null
        routing.shutdown()
    }

    /**
     * Stops and waits until the reading thread has released the `AudioRecord` (at most
     * [timeoutMs]), so a following recording never runs next to this one (WP51, WP68).
     */
    fun stopAndWait(timeoutMs: Long) {
        val t = thread
        state.stopForHandoff()
        thread = null
        routing.shutdown()
        try {
            t?.join(timeoutMs)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
    }
}

/** An `AudioRecord` as [MicTrack]. */
private class RecordTrack(private val record: AudioRecord, override val key: String?) : MicTrack {
    override val sessionId: Int = record.audioSessionId

    override fun read(buf: ByteArray, off: Int, len: Int) = record.read(buf, off, len)

    override fun readAvailable(buf: ByteArray, off: Int, len: Int) =
        record.read(buf, off, len, AudioRecord.READ_NON_BLOCKING)

    override fun release() {
        try {
            record.stop()
        } catch (_: IllegalStateException) {
            // Already stopped.
        }
        record.release()
    }
}

/**
 * Run state of [MicAudioSource]: [stopForHandoff] (WP149, [MicAudioSource.stopAndWait]) also asks for the
 * unfinished chunk to be delivered (see [readChunks]); a plain [stop] does not. [begin] resets both.
 */
internal class ReadState {
    @Volatile var running = false
        private set

    @Volatile var flushOnStop = false
        private set

    fun begin() {
        flushOnStop = false
        running = true
    }

    fun stop() {
        running = false
    }

    fun stopForHandoff() {
        flushOnStop = true
        running = false
    }
}

/** What [readChunks] reads from: the `AudioRecord` (or a fake in tests). */
internal interface PcmReader {
    /** Blocks until something is read; returns the bytes read, negative on error. */
    fun read(buf: ByteArray, off: Int, len: Int): Int

    /** Reads only what is buffered right now (no waiting); 0 if nothing, negative on error. */
    fun readAvailable(buf: ByteArray, off: Int, len: Int): Int
}

/**
 * The read loop of [MicAudioSource]: delivers chunks of [chunkBytes] while [running]. WP149: when it
 * is stopped and [flushOnStop] holds (hand-over to the app), the chunk that was just being filled
 * is delivered too, topped up with what is buffered, as a shorter chunk of whole samples. Before,
 * up to 100 ms (the unfinished chunk) were dropped at the stop, so the service's recording ended
 * before the first frame of the app's microphone and a hole of that size remained.
 */
internal fun readChunks(
    reader: PcmReader,
    chunkBytes: Int,
    running: () -> Boolean,
    flushOnStop: () -> Boolean,
    onChunk: (ByteArray) -> Unit,
) {
    val chunk = ByteArray(chunkBytes)
    var filled = 0
    while (running()) {
        while (running() && filled < chunk.size) {
            val n = reader.read(chunk, filled, chunk.size - filled)
            if (n < 0) throw IllegalStateException("AudioRecord.read: $n")
            filled += n
        }
        if (filled == chunk.size && (running() || flushOnStop())) {
            onChunk(chunk.copyOf())
            filled = 0
        }
    }
    if (!flushOnStop()) return
    if (filled < chunk.size) {
        val n = reader.readAvailable(chunk, filled, chunk.size - filled)
        if (n > 0) filled += n
    }
    val whole = filled and 1.inv()
    if (whole > 0) onChunk(chunk.copyOf(whole))
}

/**
 * Test audio for the emulator (WP20): plays a 16 kHz mono PCM16 WAV in real time, then silence,
 * like a microphone in a quiet room. Only in debuggable builds, only files in
 * `cacheDir/recognizer-test/` ([TestAudio]).
 */
class WavAudioSource(private val file: File) : RecognizerAudioSource {
    @Volatile private var running = false

    override fun start(onChunk: (ByteArray) -> Unit, onError: (Throwable) -> Unit) {
        val pcm = readPcm16(file)
        running = true
        Thread({
            val chunkBytes = RecognizerAudioSource.CHUNK_SAMPLES * 2
            val chunkMs = RecognizerAudioSource.CHUNK_SAMPLES * 1000L / RecognizerAudioSource.SAMPLE_RATE
            var offset = 0
            var sent = 0
            try {
                // At most 40 s, beyond the 30 s limit of the endpointing.
                while (running && sent < 400) {
                    val chunk = ByteArray(chunkBytes)
                    if (offset < pcm.size) {
                        val n = minOf(chunkBytes, pcm.size - offset)
                        System.arraycopy(pcm, offset, chunk, 0, n)
                        offset += n
                    }
                    onChunk(chunk)
                    sent++
                    Thread.sleep(chunkMs)
                }
            } catch (e: InterruptedException) {
                // Stopped.
            } catch (e: Throwable) {
                if (running) onError(e)
            }
        }, "wendelin-recognizer-wav").start()
    }

    override fun stop() {
        running = false
    }

    companion object {
        /** The `data` chunk of a 16 kHz mono PCM16 WAV file. */
        fun readPcm16(file: File): ByteArray = RandomAccessFile(file, "r").use { raf ->
            val bytes = ByteArray(raf.length().toInt())
            raf.readFully(bytes)
            val buf = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
            require(String(bytes, 0, 4) == "RIFF" && String(bytes, 8, 4) == "WAVE") { "no WAV" }
            var pos = 12
            var format: Pair<Int, Int>? = null
            while (pos + 8 <= bytes.size) {
                val id = String(bytes, pos, 4)
                val size = buf.getInt(pos + 4)
                val body = pos + 8
                when (id) {
                    "fmt " -> format = buf.getShort(body + 2).toInt() to buf.getInt(body + 4)
                    "data" -> {
                        require(format == 1 to RecognizerAudioSource.SAMPLE_RATE) {
                            "WAV must be 16 kHz mono"
                        }
                        return bytes.copyOfRange(body, minOf(body + size, bytes.size))
                    }
                }
                pos = body + size + (size and 1)
            }
            throw IllegalArgumentException("WAV without data")
        }
    }
}

/**
 * Emulator tests feed a WAV file instead of the microphone: the extra [EXTRA_AUDIO_FILE] names
 * a file in `cacheDir/recognizer-test/`. Ignored unless the app is debuggable, so release
 * builds always record from the microphone.
 */
object TestAudio {
    const val EXTRA_AUDIO_FILE = "app.wendelin.test.AUDIO_FILE"
    private val plainName = Regex("^[A-Za-z0-9][A-Za-z0-9._-]*$")

    fun source(context: Context, intent: Intent?): RecognizerAudioSource? {
        val name = intent?.getStringExtra(EXTRA_AUDIO_FILE) ?: return null
        val debuggable = context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        if (!debuggable || !plainName.matches(name)) return null
        val file = File(File(context.cacheDir, "recognizer-test"), name)
        if (!file.isFile) {
            Log.w("WendelinRecognizer", "Test audio missing")
            return null
        }
        return WavAudioSource(file)
    }
}
