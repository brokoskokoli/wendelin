package app.wendelin

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.service.voice.VoiceInteractionService

/**
 * Makes Wendelin selectable as the system assistant (long press on the power button, assistant
 * gesture, headset button). Everything happens in [WendelinVoiceSession]; metadata in
 * res/xml/voice_interaction_service.xml.
 *
 * With the role it also brings the wake-word service back (WP50): `onReady` starts it after a
 * restart, and the charging events (registered here, no `BOOT_COMPLETED`) start and stop it in
 * mode „nur beim Laden“. A wake word hit opens the assistant through [show].
 */
class WendelinVoiceInteractionService : VoiceInteractionService() {
    private val power = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val connected = intent.action == Intent.ACTION_POWER_CONNECTED
            WakeStarter.sync(context, if (connected) "charge" else "unplug")
        }
    }
    private var powerRegistered = false

    /** The system bound Wendelin as the active assistant. */
    override fun onReady() {
        super.onReady()
        current = this
        RecognizerSwitch.sync(this, RecognizerSwitch.Trigger.READY)
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(power, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(power, filter)
        }
        powerRegistered = true
        WakeStarter.sync(this, "vis")
    }

    override fun onShutdown() {
        if (current === this) current = null
        // First what must happen, then the cleanup that may throw: an exception here kills the
        // process before the recognizer is switched off (seen once in the emulator run).
        // isRoleHeld can still report the old holder here (race): disable without asking.
        RecognizerSwitch.sync(this, RecognizerSwitch.Trigger.SHUTDOWN)
        // The role may be gone: the wake word needs it (decision 5).
        WakeStarter.sync(this, "vis-shutdown")
        if (powerRegistered) {
            powerRegistered = false
            try {
                unregisterReceiver(power)
            } catch (e: IllegalArgumentException) {
                VoiceLog.i("vis-shutdown receiver already gone")
            }
        }
        super.onShutdown()
    }

    companion object {
        /** Session argument: the assistant was called by the wake word, not by a button. */
        const val EXTRA_WAKE = "app.wendelin.assistant.wake"

        @Volatile private var current: WendelinVoiceInteractionService? = null

        /** Opens the assistant as if called by a button (wake word); `false` if it is not bound. */
        fun show(): Boolean {
            val service = current ?: return false
            return try {
                service.showSession(Bundle().apply { putBoolean(EXTRA_WAKE, true) }, 0)
                true
            } catch (e: Exception) {
                VoiceLog.i("wake-hit error=${e.javaClass.simpleName}")
                false
            }
        }
    }
}
