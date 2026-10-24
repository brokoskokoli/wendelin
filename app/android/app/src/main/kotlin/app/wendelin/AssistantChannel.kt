package app.wendelin

import android.app.Activity
import android.app.KeyguardManager
import android.app.role.RoleManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform side of `AssistantPlatform` (app/lib/platform/assistant_platform.dart): default
 * assistant status and settings, lock state, unlock request, closing the overlay, the
 * `trigger` call to Dart when the assistant is invoked again, the audio of a wake word hit
 * (`takeWakeHandoff`, WP50), and the system speech recognizer
 * (offered to other apps, speech settings mirrored for it; [RecognizerSwitch]).
 */
class AssistantChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)

    private val unlockGuard = UnlockGuard(SystemClock::elapsedRealtime)

    /**
     * Whether an unlock request (keyguard) is showing or just ended: the lifecycle changes of
     * the keyguard transition are not "leaving the overlay" (WP114, K85).
     */
    val unlocking: Boolean
        get() = unlockGuard.active()

    /** Milliseconds until [unlocking] can end (0 if it is not on). */
    fun unlockingRemainingMs(): Long = unlockGuard.remainingMs()

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    /** Reports a new invocation of the assistant to Dart. */
    fun trigger() {
        channel.invokeMethod("trigger", null)
    }

    private var holdClose: (() -> Unit)? = null

    /**
     * The overlay is being left: Dart stops listening, speech output and the request, then
     * calls `finish`. [fallback] runs once with how it ended: `dart` (answered), `dart-error`,
     * `not-implemented` or `timeout` (no answer within [CLOSE_TIMEOUT_MS]).
     */
    fun requestClose(fallback: (how: String) -> Unit) {
        val main = Handler(Looper.getMainLooper())
        var done = false
        lateinit var timeout: Runnable
        val finishOnce = { how: String ->
            if (!done) {
                done = true
                holdClose = null
                main.removeCallbacks(timeout)
                fallback(how)
            }
        }
        timeout = Runnable { finishOnce("timeout") }
        main.postDelayed(timeout, CLOSE_TIMEOUT_MS)
        // Dart still frees a model that was loading when the overlay closed (WP145): the engine
        // must not end before, or the model would stay loaded in the process.
        holdClose = {
            main.removeCallbacks(timeout)
            main.postDelayed(timeout, CLOSE_HOLD_MS)
        }
        channel.invokeMethod("close", null, object : MethodChannel.Result {
            override fun success(result: Any?) = finishOnce("dart")
            override fun error(code: String, message: String?, details: Any?) =
                finishOnce("dart-error")
            override fun notImplemented() = finishOnce("not-implemented")
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "holdClose" -> {
                holdClose?.invoke()
                result.success(null)
            }
            "isDefaultAssistant" -> result.success(isDefaultAssistant())
            "openAssistantSettings" -> result.success(openAssistantSettings())
            "isLocked" -> result.success(keyguard().isKeyguardLocked)
            "requestUnlock" -> requestUnlock(result)
            "isRecognizerOffered" -> result.success(RecognizerSwitch.isOffered(activity))
            "recognitionServiceState" -> RecognitionServiceStatus.read(activity) { result.success(it) }
            "setRecognizerOffered" -> {
                RecognizerSwitch.setOffered(activity, call.argument<Boolean>("offered") != false)
                result.success(null)
            }
            "setRecognizerConfig" -> {
                RecognizerConfig.fromArgs(call.arguments as? Map<*, *>).save(activity)
                result.success(null)
            }
            "hasWakeHandoff" -> result.success(WakeHandoff.pending())
            "takeWakeHandoff" -> {
                // The chat of the main app gets the audio only for a hit it owns (WP93).
                if (!WakePolicy.mayTakeHandoff(activity is MainActivity, ChatState.owned)) {
                    VoiceLog.i("wake-handoff-take refused (chat does not own the hit)")
                    result.success(null)
                    return
                }
                val closeAt = System.currentTimeMillis()
                if (WakeHandoff.pending()) WakeWordService.beforeHandoffTake()
                val closeMs = System.currentTimeMillis() - closeAt
                val taken = WakeHandoff.take(System.currentTimeMillis())
                if (taken != null) {
                    WakeWordService.onHandoffTaken()
                    VoiceLog.i("wake-handoff-take captured=${taken.capturedMs}ms close=${closeMs}ms")
                }
                result.success(
                    taken?.let {
                        mapOf(
                            "pcm" to it.pcm,
                            "wakeEnd" to it.wakeEnd,
                            "capturedMs" to it.capturedMs,
                            "lastSampleAt" to it.lastSampleAtMs,
                        )
                    },
                )
            }
            "finish" -> {
                // The station closes only after the keyguard was dismissed (WP99).
                val done = StationPolicy.finishIfAllowed(
                    activity is StationActivity,
                    keyguard().isKeyguardLocked,
                ) {
                    VoiceLog.i("overlay-finish finishing=${activity.isFinishing}")
                    activity.finish()
                }
                if (!done) VoiceLog.i("station-finish refused (device locked)")
                result.success(done)
            }
            else -> result.notImplemented()
        }
    }

    private fun keyguard() = activity.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager

    private fun isDefaultAssistant(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roles = activity.getSystemService(RoleManager::class.java)
            return roles?.isRoleHeld(RoleManager.ROLE_ASSISTANT) == true
        }
        val current = Settings.Secure.getString(activity.contentResolver, "assistant") ?: return false
        return ComponentName.unflattenFromString(current)?.packageName == activity.packageName
    }

    /** Assistant choice: voice input settings (concept), else default apps, else settings. */
    private fun openAssistantSettings(): Boolean {
        for (action in listOf(
            Settings.ACTION_VOICE_INPUT_SETTINGS,
            Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS,
            Settings.ACTION_SETTINGS,
        )) {
            try {
                activity.startActivity(Intent(action))
                return true
            } catch (e: ActivityNotFoundException) {
                // Try the next one.
            }
        }
        return false
    }

    private fun requestUnlock(result: MethodChannel.Result) {
        val keyguard = keyguard()
        if (!keyguard.isKeyguardLocked) {
            result.success(true)
            return
        }
        unlockGuard.begin()
        keyguard.requestDismissKeyguard(activity, object : KeyguardManager.KeyguardDismissCallback() {
            override fun onDismissSucceeded() = done(true)
            override fun onDismissCancelled() = done(false)
            override fun onDismissError() = done(false)

            private fun done(ok: Boolean) {
                unlockGuard.end()
                result.success(ok)
            }
        })
    }

    companion object {
        const val CHANNEL = "app.wendelin/assistant"
        private const val CLOSE_TIMEOUT_MS = 1000L
        private const val CLOSE_HOLD_MS = 14_000L
    }
}
