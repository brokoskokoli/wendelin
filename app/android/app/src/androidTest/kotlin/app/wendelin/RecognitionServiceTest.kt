package app.wendelin

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.AfterClass
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.FixMethodOrder
import org.junit.Test
import org.junit.runners.MethodSorters

/**
 * Emulator test of the system speech recognizer (WP20): a client calls [SpeechRecognizer] on
 * [WendelinRecognitionService] with a WAV fixture instead of the microphone ([TestAudio]).
 *
 * Needs (tool/e2e_recognizer.sh): Whisper base and Silero in the app data, the app installed
 * without the microphone permission (the first test checks that path, then grants it).
 * Runs in the order of the method names.
 */
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class RecognitionServiceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    /** What the client saw. */
    class Outcome {
        val events: MutableList<String> = java.util.concurrent.CopyOnWriteArrayList()
        var error: Int? = null
        var results: List<String> = emptyList()
        var confidence: Float? = null
        val done = CountDownLatch(1)
        val began = CountDownLatch(1)

        override fun toString() = "events=$events error=$error results=$results"
    }

    @Before
    fun setUp() {
        if (!RecognizerSwitch.holdsAssistantRole(context)) {
            shell("cmd role add-role-holder --user 0 android.app.role.ASSISTANT ${context.packageName}")
            waitUntil(10_000) { RecognizerSwitch.holdsAssistantRole(context) }
        }
        RecognizerSwitch.setOffered(context, true)
        RecognizerConfig(language = "de").save(context)
    }

    /**
     * Client and service share the app's uid here, so this path checks Wendelin's own
     * permission and that of the caller at once: on Android 12+ the framework rejects the
     * caller first, `WendelinRecognitionService.mayRecord` (own permission, the caller's
     * permission and app op) is the second check. A separate client app would be needed to
     * reach only the second one (WP19).
     */
    @Test
    fun a_withoutMicrophonePermission_insufficientPermissions() {
        assertTrue(
            "Die App muss ohne Mikrofon-Berechtigung installiert sein",
            context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
                PackageManager.PERMISSION_GRANTED,
        )
        val outcome = recognize("en-01.wav", language = "en-US")
        assertEquals(outcome.toString(), SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS, outcome.error)
        // Granting does not restart the process (revoking would).
        shell("pm grant ${context.packageName} ${Manifest.permission.RECORD_AUDIO}")
        waitUntil(5_000) {
            context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
        }
    }

    @Test
    fun b_englishWav_recognizedWithExtraLanguage() {
        val outcome = recognize("en-01.wav", language = "en-US")
        assertEquals(outcome.toString(), null, outcome.error)
        val text = outcome.results.single().lowercase()
        // „Add milk and bread to the shopping list.“
        for (word in listOf("milk", "bread", "shopping", "list")) {
            assertTrue("$word in „$text“", text.contains(word))
        }
        assertEquals(listOf("ready", "rms", "begin", "end", "results"), outcome.events.distinct())
        assertTrue((outcome.confidence ?: -1f) in 0f..1f)
    }

    @Test
    fun c_germanWav_languageFromSettings() {
        val outcome = recognize("de-05.wav", language = null)
        assertEquals(outcome.toString(), null, outcome.error)
        val text = outcome.results.single().lowercase()
        // „Ergänze in meiner Tagesnotiz, dass ich den Zahnarzt angerufen habe.“
        for (word in listOf("tagesnotiz", "zahnarzt")) {
            assertTrue("$word in „$text“", text.contains(word))
        }
    }

    @Test
    fun d_silence_speechTimeout() {
        val outcome = recognize(silenceWav(), language = "de-DE")
        assertEquals(outcome.toString(), SpeechRecognizer.ERROR_SPEECH_TIMEOUT, outcome.error)
        assertTrue(outcome.toString(), "begin" !in outcome.events)
    }

    @Test
    fun d2_stopWithoutSpeech_noMatch() {
        val recognizer = create()
        val outcome = Outcome()
        start(recognizer, outcome, silenceWav(), "de-DE")
        Thread.sleep(2000)
        instrumentation.runOnMainSync { recognizer.stopListening() }
        assertTrue(outcome.toString(), outcome.done.await(30, TimeUnit.SECONDS))
        instrumentation.runOnMainSync { recognizer.destroy() }
        assertEquals(outcome.toString(), SpeechRecognizer.ERROR_NO_MATCH, outcome.error)
    }

    @Test
    fun e_modelMissing_client() {
        RecognizerConfig(model = "whisper-small", language = "de").save(context)
        val outcome = recognize("de-05.wav", language = null)
        assertEquals(outcome.toString(), SpeechRecognizer.ERROR_CLIENT, outcome.error)
    }

    @Test
    fun f_unsupportedLanguage() {
        val outcome = recognize("en-01.wav", language = "es-ES")
        assertEquals(
            outcome.toString(),
            SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED,
            outcome.error,
        )
    }

    @Test
    fun g_cancel_noFurtherCallbacks_thenNextRequestWorks() {
        val recognizer = create()
        val outcome = Outcome()
        start(recognizer, outcome, "en-01.wav", "en-US")
        assertTrue("Sprachbeginn", outcome.began.await(30, TimeUnit.SECONDS))
        instrumentation.runOnMainSync { recognizer.cancel() }
        // Microphone off at once: after a short grace no more levels or other callbacks.
        Thread.sleep(500)
        val afterCancel = outcome.events.size
        assertTrue(outcome.toString(), !outcome.done.await(12, TimeUnit.SECONDS))
        assertEquals(outcome.toString(), afterCancel, outcome.events.size)
        // The same client can start again.
        val next = Outcome()
        start(recognizer, next, "en-07.wav", "en-US")
        assertTrue(next.toString(), next.done.await(60, TimeUnit.SECONDS))
        instrumentation.runOnMainSync { recognizer.destroy() }
        assertEquals(next.toString(), null, next.error)
        assertTrue(next.results.single().lowercase().contains("note"))
    }

    @Test
    fun g2_cancelRightAfterStart_microphoneOff() {
        // Cancel before Dart has started the session: the microphone must stop in Kotlin.
        val recognizer = create()
        val outcome = Outcome()
        start(recognizer, outcome, "en-06.wav", "en-US", cancelRightAway = true)
        Thread.sleep(300)
        val seen = outcome.events.size
        assertTrue(outcome.toString(), !outcome.done.await(3, TimeUnit.SECONDS))
        instrumentation.runOnMainSync { recognizer.destroy() }
        assertEquals(outcome.toString(), seen, outcome.events.size)
    }

    @Test
    fun h_stopListening_recognizesSpeechSoFar() {
        val recognizer = create()
        val outcome = Outcome()
        // „Append to my daily note that the meeting moved to Friday.“
        start(recognizer, outcome, "en-06.wav", "en-US")
        assertTrue("Sprachbeginn", outcome.began.await(30, TimeUnit.SECONDS))
        Thread.sleep(1200)
        instrumentation.runOnMainSync { recognizer.stopListening() }
        assertTrue(outcome.toString(), outcome.done.await(60, TimeUnit.SECONDS))
        instrumentation.runOnMainSync { recognizer.destroy() }
        assertEquals(outcome.toString(), null, outcome.error)
        val text = outcome.results.single().lowercase()
        assertTrue(text, text.contains("append") || text.contains("daily"))
        assertTrue(text, !text.contains("friday"))
    }

    @Test
    fun h2_realMicrophone_opensWithCallerAttribution() {
        // Emulator microphone (silence or host audio): AudioRecord with the caller's
        // attribution opens, the levels arrive, and the request ends cleanly.
        val outcome = recognize(null, language = "de-DE")
        assertTrue(outcome.toString(), outcome.events.take(2) == listOf("ready", "rms"))
        assertTrue(
            outcome.toString(),
            outcome.error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT ||
                outcome.error == SpeechRecognizer.ERROR_NO_MATCH ||
                outcome.error == null,
        )
    }

    @Test
    fun h3_stopDuringColdStart_microphoneOffAtOnce() {
        // A fresh service starts its engine with every recognizer; stop right away, while
        // Dart is still starting (start, audio and stop are queued in Kotlin).
        val recognizer = create()
        val outcome = Outcome()
        // „Append to my daily note that the meeting moved to Friday.“ (≈ 4 s of speech)
        // Stop right behind the start: Dart is still checking the models (or the engine is
        // still starting) when the stop arrives.
        start(recognizer, outcome, "en-06.wav", "en-US", stopRightAway = true)
        val stoppedAt = System.currentTimeMillis()
        Thread.sleep(300)
        val levels = outcome.events.count { it == "rms" }
        assertTrue(outcome.toString(), outcome.done.await(30, TimeUnit.SECONDS))
        val tookMs = System.currentTimeMillis() - stoppedAt
        instrumentation.runOnMainSync { recognizer.destroy() }
        // The microphone stopped with stopListening: no levels afterwards, and the answer does
        // not wait for the end of the sentence (≈ 4 s + 0.8 s silence).
        assertEquals(outcome.toString(), levels, outcome.events.count { it == "rms" })
        assertTrue("$tookMs ms: $outcome", tookMs < 3500)
        assertTrue(
            outcome.toString(),
            outcome.error == SpeechRecognizer.ERROR_NO_MATCH ||
                (outcome.error == null && !outcome.results.single().lowercase().contains("friday")),
        )
    }

    @Test
    fun h4_callerAudioSource_rejected() {
        val recognizer = create()
        val outcome = Outcome()
        val pipe = ParcelFileDescriptor.createPipe()
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, pipe[0])
        }
        instrumentation.runOnMainSync {
            recognizer.setRecognitionListener(listener(outcome))
            recognizer.startListening(intent)
        }
        assertTrue(outcome.toString(), outcome.done.await(30, TimeUnit.SECONDS))
        instrumentation.runOnMainSync { recognizer.destroy() }
        pipe.forEach { it.close() }
        assertEquals(outcome.toString(), SpeechRecognizer.ERROR_CLIENT, outcome.error)
    }

    @Test
    fun i_notOffered_serviceDisabled() {
        RecognizerSwitch.setOffered(context, false)
        assertEquals(
            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT,
            context.packageManager.getComponentEnabledSetting(component()),
        )
        val outcome = recognize("en-01.wav", language = "en-US", timeoutS = 15)
        assertTrue(outcome.toString(), outcome.error != null)
        assertTrue(outcome.toString(), outcome.results.isEmpty())
        // Wendelin stays the assistant without the recognizer.
        assertTrue(RecognizerSwitch.holdsAssistantRole(context))
        assertTrue(
            shell("settings get secure voice_interaction_service")
                .startsWith("${context.packageName}/"),
        )
        assertTrue(shell("dumpsys voiceinteraction").contains("WendelinVoiceInteractionService"))
        RecognizerSwitch.setOffered(context, true)
        assertEquals(
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            context.packageManager.getComponentEnabledSetting(component()),
        )
    }

    // --- helpers ---

    private fun component() = ComponentName(context, WendelinRecognitionService::class.java)

    private fun create(): SpeechRecognizer {
        var recognizer: SpeechRecognizer? = null
        instrumentation.runOnMainSync {
            recognizer = SpeechRecognizer.createSpeechRecognizer(context, component())
        }
        return recognizer!!
    }

    /** Starts a request; [wav] `null` = the real microphone. */
    private fun start(
        recognizer: SpeechRecognizer,
        outcome: Outcome,
        wav: String?,
        language: String?,
        stopRightAway: Boolean = false,
        cancelRightAway: Boolean = false,
    ) {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            if (language != null) putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
            if (wav != null) putExtra(TestAudio.EXTRA_AUDIO_FILE, fixture(wav))
        }
        instrumentation.runOnMainSync {
            recognizer.setRecognitionListener(listener(outcome))
            recognizer.startListening(intent)
            if (stopRightAway) recognizer.stopListening()
            if (cancelRightAway) recognizer.cancel()
        }
    }

    private fun recognize(wav: String?, language: String?, timeoutS: Long = 60): Outcome {
        val recognizer = create()
        val outcome = Outcome()
        start(recognizer, outcome, wav, language)
        val finished = outcome.done.await(timeoutS, TimeUnit.SECONDS)
        instrumentation.runOnMainSync { recognizer.destroy() }
        assertTrue("keine Antwort: $outcome", finished)
        return outcome
    }

    private fun listener(outcome: Outcome) = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) { outcome.events += "ready" }
        override fun onBeginningOfSpeech() {
            outcome.events += "begin"
            outcome.began.countDown()
        }
        override fun onRmsChanged(rmsdB: Float) { outcome.events += "rms" }
        override fun onBufferReceived(buffer: ByteArray?) { outcome.events += "buffer" }
        override fun onEndOfSpeech() { outcome.events += "end" }
        override fun onError(error: Int) {
            outcome.events += "error"
            outcome.error = error
            outcome.done.countDown()
        }
        override fun onResults(results: Bundle?) {
            outcome.events += "results"
            outcome.results =
                results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION) ?: emptyList()
            outcome.confidence =
                results?.getFloatArray(SpeechRecognizer.CONFIDENCE_SCORES)?.firstOrNull()
            outcome.done.countDown()
        }
        override fun onPartialResults(partialResults: Bundle?) { outcome.events += "partial" }
        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    /** Copies the asset [name] of the test APK to the test audio folder of the app. */
    private fun fixture(name: String): String {
        val dir = File(context.cacheDir, "recognizer-test").apply { mkdirs() }
        val target = File(dir, name)
        if (!target.exists()) {
            instrumentation.context.assets.open(name).use { input ->
                target.outputStream().use { input.copyTo(it) }
            }
        }
        return name
    }

    /** A 1 s WAV of digital silence (the source pads with silence afterwards). */
    private fun silenceWav(): String {
        val dir = File(context.cacheDir, "recognizer-test").apply { mkdirs() }
        val samples = 16000
        val buf = ByteBuffer.allocate(44 + samples * 2).order(ByteOrder.LITTLE_ENDIAN)
        buf.put("RIFF".toByteArray()).putInt(36 + samples * 2).put("WAVE".toByteArray())
        buf.put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(1)
            .putInt(16000).putInt(32000).putShort(2).putShort(16)
        buf.put("data".toByteArray()).putInt(samples * 2)
        File(dir, "silence.wav").writeBytes(buf.array())
        return "silence.wav"
    }

    private fun shell(command: String): String {
        val pfd = instrumentation.uiAutomation.executeShellCommand(command)
        return ParcelFileDescriptor.AutoCloseInputStream(pfd).use { input: FileInputStream ->
            input.readBytes().toString(Charsets.UTF_8)
        }
    }

    private fun waitUntil(timeoutMs: Long, condition: () -> Boolean) {
        val end = System.currentTimeMillis() + timeoutMs
        while (!condition()) {
            assertTrue("Zeitüberschreitung", System.currentTimeMillis() < end)
            Thread.sleep(100)
        }
    }

    companion object {
        @JvmStatic
        @AfterClass
        fun tearDown() {
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            val pkg = instrumentation.targetContext.packageName
            instrumentation.uiAutomation
                .executeShellCommand("cmd role remove-role-holder --user 0 android.app.role.ASSISTANT $pkg")
                .close()
        }
    }
}
