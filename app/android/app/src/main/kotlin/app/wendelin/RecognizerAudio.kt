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

/** The microphone (`AudioRecord`, source `VOICE_RECOGNITION`), attributed to the calling app. */
class MicAudioSource(private val context: Context) : RecognizerAudioSource {
    @Volatile private var running = false
    private var thread: Thread? = null

    @SuppressLint("MissingPermission") // Checked by the service before.
    override fun start(onChunk: (ByteArray) -> Unit, onError: (Throwable) -> Unit) {
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
        record.startRecording()
        running = true
        thread = Thread({
            val chunk = ByteArray(RecognizerAudioSource.CHUNK_SAMPLES * 2)
            try {
                while (running) {
                    var filled = 0
                    while (running && filled < chunk.size) {
                        val n = record.read(chunk, filled, chunk.size - filled)
                        if (n < 0) throw IllegalStateException("AudioRecord.read: $n")
                        filled += n
                    }
                    if (running) onChunk(chunk.copyOf())
                }
            } catch (e: Throwable) {
                if (running) onError(e)
            } finally {
                record.stop()
                record.release()
            }
        }, "wendelin-recognizer-mic").also { it.start() }
    }

    override fun stop() {
        running = false
        thread = null
    }
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
