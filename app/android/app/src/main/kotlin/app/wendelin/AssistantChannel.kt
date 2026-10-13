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
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform side of `AssistantPlatform` (app/lib/platform/assistant_platform.dart): default
 * assistant status and settings, lock state, unlock request, closing the overlay, and the
 * `trigger` call to Dart when the assistant is invoked again.
 */
class AssistantChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)

    /** Whether an unlock request (keyguard) is showing. */
    var unlocking = false
        private set

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

    /**
     * The overlay is being left: Dart stops listening, speech output and the request, then
     * calls `finish`. [fallback] runs if Dart does not answer within [CLOSE_TIMEOUT_MS].
     */
    fun requestClose(fallback: () -> Unit) {
        val main = Handler(Looper.getMainLooper())
        var done = false
        val finishOnce = {
            if (!done) {
                done = true
                fallback()
            }
        }
        main.postDelayed(finishOnce, CLOSE_TIMEOUT_MS)
        channel.invokeMethod("close", null, object : MethodChannel.Result {
            override fun success(result: Any?) = finishOnce()
            override fun error(code: String, message: String?, details: Any?) = finishOnce()
            override fun notImplemented() = finishOnce()
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isDefaultAssistant" -> result.success(isDefaultAssistant())
            "openAssistantSettings" -> result.success(openAssistantSettings())
            "isLocked" -> result.success(keyguard().isKeyguardLocked)
            "requestUnlock" -> requestUnlock(result)
            "finish" -> {
                activity.finish()
                result.success(null)
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
        unlocking = true
        keyguard.requestDismissKeyguard(activity, object : KeyguardManager.KeyguardDismissCallback() {
            override fun onDismissSucceeded() = done(true)
            override fun onDismissCancelled() = done(false)
            override fun onDismissError() = done(false)

            private fun done(ok: Boolean) {
                unlocking = false
                result.success(ok)
            }
        })
    }

    companion object {
        const val CHANNEL = "app.wendelin/assistant"
        private const val CLOSE_TIMEOUT_MS = 1000L
    }
}
