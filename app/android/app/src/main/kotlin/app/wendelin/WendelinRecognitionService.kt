package app.wendelin

import android.content.Intent
import android.speech.RecognitionService
import android.speech.SpeechRecognizer

/**
 * Required by Android for every `VoiceInteractionService` (`recognitionService` in the
 * metadata). Wendelin recognizes speech inside the app (Whisper, WP17); this system recognizer
 * for other apps is not offered yet and answers every request with an error.
 */
class WendelinRecognitionService : RecognitionService() {
    override fun onStartListening(recognizerIntent: Intent?, listener: Callback?) {
        listener?.error(SpeechRecognizer.ERROR_CLIENT)
    }

    override fun onStopListening(listener: Callback?) {}

    override fun onCancel(listener: Callback?) {}
}
