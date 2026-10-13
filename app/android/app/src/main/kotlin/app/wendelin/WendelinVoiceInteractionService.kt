package app.wendelin

import android.service.voice.VoiceInteractionService

/**
 * Makes Wendelin selectable as the system assistant (long press on the power button, assistant
 * gesture, headset button). Everything happens in [WendelinVoiceSession]; metadata in
 * res/xml/voice_interaction_service.xml.
 */
class WendelinVoiceInteractionService : VoiceInteractionService()
