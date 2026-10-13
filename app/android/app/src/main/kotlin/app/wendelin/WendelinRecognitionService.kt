package app.wendelin

import android.Manifest
import android.app.AppOpsManager
import android.content.ContextParams
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.RemoteException
import android.speech.RecognitionService
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import io.flutter.plugin.common.MethodCall

/**
 * Wendelin as the system speech recognizer for other apps (WP20, ADR 0008): records here (with
 * the caller's attribution), recognizes in a headless Flutter engine with Silero VAD, the
 * pipeline's endpointing (800 ms silence, at most 30 s) and Whisper, all on the device.
 * Audio is never stored.
 *
 * Android requires this service for every `VoiceInteractionService`. It is enabled only while
 * Wendelin holds the assistant role and the user offers it ([RecognizerSwitch]).
 *
 * Callbacks: `onReadyForSpeech` when the microphone is open, `onRmsChanged` per 100 ms,
 * `onBeginningOfSpeech`, `onEndOfSpeech`, `onResults` (one hypothesis, with a confidence).
 * No partial results: Whisper recognizes the whole utterance at once.
 */
class WendelinRecognitionService : RecognitionService() {
    private val main = Handler(Looper.getMainLooper())
    private var engine: RecognizerEngine? = null
    private var session: Session? = null
    private var nextId = 0

    private inner class Session(
        val id: Int,
        val listener: Callback,
        val audio: RecognizerAudioSource,
    ) {
        var audioOpen = false
        val watchdog = Runnable { finish(SpeechRecognizer.ERROR_CLIENT, "Zeitüberschreitung") }

        fun stopAudio() {
            if (audioOpen) {
                audioOpen = false
                audio.stop()
            }
        }

        /** Ends the session with an error (no further callbacks). */
        fun finish(error: Int, reason: String) {
            if (session !== this) return
            Log.i(TAG, "Erkennung beendet: Fehler $error ($reason)")
            close()
            engine?.send("cancel", mapOf("session" to id))
            notify { listener.error(error) }
        }

        fun close() {
            stopAudio()
            main.removeCallbacks(watchdog)
            if (session === this) session = null
        }
    }

    override fun onStartListening(recognizerIntent: Intent?, listener: Callback?) {
        listener ?: return
        session?.let {
            // The framework allows one request per client; a new one replaces an old one.
            it.close()
            engine?.send("cancel", mapOf("session" to it.id))
        }
        if (!RecognizerSwitch.isActive(this)) {
            RecognizerSwitch.sync(this)
            notify { listener.error(SpeechRecognizer.ERROR_CLIENT) }
            return
        }
        if (!mayRecord(listener)) {
            notify { listener.error(SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) }
            return
        }
        if (recognizerIntent?.hasExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE) == true) {
            // Audio from the caller (Android 13) is not supported: Wendelin only records itself.
            Log.i(TAG, "EXTRA_AUDIO_SOURCE wird nicht unterstützt")
            notify { listener.error(SpeechRecognizer.ERROR_CLIENT) }
            return
        }
        val id = ++nextId
        val audio = TestAudio.source(this, recognizerIntent) ?: MicAudioSource(attributedContext(listener))
        val s = Session(id, listener, audio)
        session = s
        val engine = try {
            engine ?: RecognizerEngine(this, ::onDartCall).also { engine = it }
        } catch (e: Exception) {
            Log.e(TAG, "Erkenner-Engine startet nicht", e)
            s.finish(SpeechRecognizer.ERROR_CLIENT, "Engine")
            return
        }
        main.postDelayed(s.watchdog, SESSION_TIMEOUT_MS)
        val language = recognizerIntent?.getStringExtra(RecognizerIntent.EXTRA_LANGUAGE)
        engine.send(
            "start",
            RecognizerConfig.load(this).toArgs() + mapOf("session" to id, "language" to language),
        )
        try {
            audio.start(
                onChunk = { chunk -> main.post { onChunk(s, chunk) } },
                onError = { e ->
                    main.post {
                        Log.w(TAG, "Mikrofon ausgefallen: ${e.javaClass.simpleName}")
                        if (session === s) {
                            s.stopAudio()
                            engine.send("audioError", mapOf("session" to id, "code" to "audio"))
                        }
                    }
                },
            )
            s.audioOpen = true
        } catch (e: SecurityException) {
            s.finish(SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS, "Mikrofon verweigert")
            return
        } catch (e: Exception) {
            s.finish(SpeechRecognizer.ERROR_AUDIO, "Mikrofon: ${e.javaClass.simpleName}")
            return
        }
        notify { listener.readyForSpeech(Bundle()) }
    }

    private fun onChunk(s: Session, chunk: ByteArray) {
        if (session !== s || !s.audioOpen) return
        notify { s.listener.rmsChanged(RecognizerAudioSource.rmsDb(chunk)) }
        engine?.send("audio", mapOf("session" to s.id, "pcm" to chunk))
    }

    /** Events of the recognizer engine. */
    private fun onDartCall(call: MethodCall) {
        val s = session ?: return
        if ((call.argument<Any>("session") as? Number)?.toInt() != s.id) return
        when (call.method) {
            "stopAudio" -> s.stopAudio()
            "event" -> when (call.argument<String>("type")) {
                "began" -> notify { s.listener.beginningOfSpeech() }
                "ended" -> {
                    s.stopAudio()
                    notify { s.listener.endOfSpeech() }
                }
                "result" -> {
                    s.close()
                    val text = call.argument<String>("text") ?: ""
                    val confidence = (call.argument<Any>("confidence") as? Number)?.toFloat() ?: -1f
                    val results = Bundle().apply {
                        putStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION, arrayListOf(text))
                        putFloatArray(SpeechRecognizer.CONFIDENCE_SCORES, floatArrayOf(confidence))
                    }
                    Log.i(TAG, "Erkennung fertig (${text.length} Zeichen)")
                    notify { s.listener.results(results) }
                }
                "error" -> s.finish(
                    errorCode(call.argument<String>("error")),
                    call.argument<String>("message") ?: "",
                )
            }
        }
    }

    override fun onStopListening(listener: Callback?) {
        val s = session ?: return
        // Microphone off right away (also while the engine is still starting); Dart recognizes
        // the audio received so far.
        s.stopAudio()
        engine?.send("stop", mapOf("session" to s.id))
    }

    override fun onCancel(listener: Callback?) {
        val s = session ?: return
        s.close()
        engine?.send("cancel", mapOf("session" to s.id))
    }

    override fun onDestroy() {
        session?.close()
        engine?.destroy()
        engine = null
        super.onDestroy()
    }

    /**
     * Whether Wendelin may record for this caller: its own `RECORD_AUDIO` and, from Android 12,
     * the calling app's (from its `AttributionSource`): runtime permission and app op, checked
     * without noting an access. The framework checks the caller before as well.
     */
    private fun mayRecord(listener: Callback): Boolean {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            return false
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val caller = listener.callingAttributionSource
        if (checkPermission(Manifest.permission.RECORD_AUDIO, -1, caller.uid) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        val mode = getSystemService(AppOpsManager::class.java).unsafeCheckOpNoThrow(
            AppOpsManager.OPSTR_RECORD_AUDIO,
            caller.uid,
            caller.packageName ?: return false,
        )
        return mode == AppOpsManager.MODE_ALLOWED ||
            mode == AppOpsManager.MODE_FOREGROUND ||
            mode == AppOpsManager.MODE_DEFAULT
    }

    /** Context whose recordings count for the calling app (Android 12+). */
    private fun attributedContext(listener: Callback) =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                createContext(
                    ContextParams.Builder()
                        .setNextAttributionSource(listener.callingAttributionSource)
                        .build(),
                )
            } catch (e: Exception) {
                this
            }
        } else {
            this
        }

    /** Calls the client; it may have gone away meanwhile. */
    private inline fun notify(block: () -> Unit) {
        try {
            block()
        } catch (e: RemoteException) {
            Log.w(TAG, "Client nicht erreichbar")
        }
    }

    companion object {
        private const val TAG = "WendelinRecognizer"

        /** Listening (≤ 30 s) plus engine start and transcription. */
        private const val SESSION_TIMEOUT_MS = 90_000L

        /** `SpeechRecognizer` error for a failure kind of the Dart session. */
        fun errorCode(kind: String?): Int = when (kind) {
            "noMatch" -> SpeechRecognizer.ERROR_NO_MATCH
            "speechTimeout" -> SpeechRecognizer.ERROR_SPEECH_TIMEOUT
            "audio" -> SpeechRecognizer.ERROR_AUDIO
            "permission" -> SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS
            "language" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED
            } else {
                SpeechRecognizer.ERROR_CLIENT
            }
            // modelMissing, client: the app has to load the models (Einstellungen → Sprache).
            else -> SpeechRecognizer.ERROR_CLIENT
        }
    }
}
