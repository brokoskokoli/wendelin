package app.wendelin

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.service.voice.VoiceInteractionSession
import android.service.voice.VoiceInteractionSessionService

/** Creates a [WendelinVoiceSession] for every invocation of the assistant. */
class WendelinVoiceSessionService : VoiceInteractionSessionService() {
    override fun onNewSession(args: Bundle?): VoiceInteractionSession = WendelinVoiceSession(this)
}

/**
 * One invocation of the assistant: starts the Flutter overlay ([AssistantActivity]), which
 * reports `TriggerKind.assistant`, and hides its own (empty) window.
 */
class WendelinVoiceSession(context: Context) : VoiceInteractionSession(context) {
    override fun onShow(args: Bundle?, showFlags: Int) {
        super.onShow(args, showFlags)
        val intent = Intent(context, AssistantActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        startAssistantActivity(intent)
        hide()
    }
}
