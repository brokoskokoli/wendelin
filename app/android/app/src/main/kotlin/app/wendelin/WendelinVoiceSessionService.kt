package app.wendelin

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.service.voice.VoiceInteractionSession
import android.service.voice.VoiceInteractionSessionService
import android.util.Log

/** Creates a [WendelinVoiceSession] for every invocation of the assistant. */
class WendelinVoiceSessionService : VoiceInteractionSessionService() {
    override fun onNewSession(args: Bundle?): VoiceInteractionSession {
        VoiceLog.i("session-new")
        return WendelinVoiceSession(this)
    }
}

/**
 * One invocation of the assistant: starts the Flutter overlay ([AssistantActivity]), which
 * reports `TriggerKind.assistant`. The session has no window of its own. It ends itself
 * (`finish()`) as soon as the overlay is there, so the next invocation gets a fresh session; if
 * the overlay does not come, it starts it once more ([AssistantLauncher], B10).
 */
class WendelinVoiceSession(context: Context) : VoiceInteractionSession(context) {
    private val main = Handler(Looper.getMainLooper())
    private val arrived: () -> Unit = { launcher.onArrived() }

    private val launcher = AssistantLauncher(
        start = { retry ->
            AssistantArrivals.await(arrived)
            // A fresh intent for every attempt.
            startAssistantActivity(
                Intent(context, AssistantActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    .putExtra(AssistantActivity.EXTRA_RETRY, retry),
            )
        },
        schedule = { delayMs, block ->
            val r = Runnable(block)
            main.postDelayed(r, delayMs)
            AssistantLauncher.Cancelable { main.removeCallbacks(r) }
        },
        end = { finish() },
        log = VoiceLog::i,
    )

    override fun onCreate() {
        super.onCreate()
        // No window: the overlay activity is the UI.
        setUiEnabled(false)
        VoiceLog.i("session-create")
    }

    override fun onShow(args: Bundle?, showFlags: Int) {
        super.onShow(args, showFlags)
        launcher.onShow(showFlags)
    }

    override fun onHide() {
        super.onHide()
        launcher.onHide()
    }

    override fun onDestroy() {
        VoiceLog.i("session-destroy pending=${launcher.pending}")
        // No retry may start an overlay for a session that is gone.
        launcher.cancel()
        AssistantArrivals.clear(arrived)
        super.onDestroy()
    }
}

/** Diagnostics without content under the tag `Wendelin/voice` (also in release builds). */
object VoiceLog {
    private const val TAG = "Wendelin/voice"

    fun i(message: String) {
        Log.i(TAG, message)
    }
}
