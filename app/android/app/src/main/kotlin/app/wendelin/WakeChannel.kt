package app.wendelin

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform side of `WakePlatform` (app/lib/platform/wake/wake_platform.dart, main app only): the
 * app mirrors the wake-word settings here (`configure`), which also starts or stops the service
 * ([WakeStarter]), and reads the state (`status`) for the settings page.
 */
class WakeChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler(this)
        current = this
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        if (current === this) current = null
        ChatState.visible = false
        // The engine goes while the chat listens: the service must not stay deaf (WP93).
        if (ChatState.release()) WakeWordService.onOverlayClosed()
    }

    /**
     * WP93: asks the main engine whether its chat takes the hit; [done] gets `true` only if it
     * does. Errors and a missing handler are `false`.
     */
    private fun ask(done: (Any?) -> Unit) {
        channel.invokeMethod(
            "wakeHit",
            null,
            object : MethodChannel.Result {
                override fun success(result: Any?) = done(result)
                override fun error(code: String, message: String?, details: Any?) = done(false)
                override fun notImplemented() = done(false)
            },
        )
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "configure" -> {
                val next = WakeSettingsStore.load(context).withArgs(call.arguments as? Map<*, *>)
                WakeSettingsStore.save(context, next)
                WakeStarter.sync(context, "app")
                result.success(null)
            }
            "status" -> {
                val s = WakeSettingsStore.load(context)
                result.success(
                    mapOf(
                        "running" to WakeWordService.running,
                        "enabled" to s.enabled,
                        "offByUser" to s.offByUser,
                        "mode" to s.mode.key,
                        "pausedUntil" to s.pausedUntilMs,
                        "holdsRole" to RecognizerSwitch.holdsAssistantRole(context),
                        "charging" to WakeStarter.isCharging(context),
                        "lastStop" to WakeSettingsStore.lastStop(context),
                    ),
                )
            }
            "chatVisible" -> {
                ChatState.visible = call.argument<Boolean>("visible") == true
                result.success(null)
            }
            // The chat turn is over (WP93): the service listens again, like after the overlay.
            "chatDone" -> {
                // Only if the chat still owns the hit (it may have lost it to the overlay).
                if (ChatState.release()) WakeWordService.onOverlayClosed()
                result.success(null)
            }
            "debugHit" -> result.success(WakeWordService.debugHit(context))
            else -> result.notImplemented()
        }
    }

    companion object {
        @Volatile private var current: WakeChannel? = null

        /** Whether a main engine can be asked (WP93). */
        val available: Boolean get() = current != null

        /** Asks the main engine (main thread); [done] gets its reply. */
        fun askHit(done: (Any?) -> Unit) {
            val c = current
            if (c == null) done(false) else c.ask(done)
        }

        const val CHANNEL = "app.wendelin/wake"
    }
}
