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
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
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
                        "mode" to s.mode.key,
                        "pausedUntil" to s.pausedUntilMs,
                        "holdsRole" to RecognizerSwitch.holdsAssistantRole(context),
                        "charging" to WakeStarter.isCharging(context),
                        "lastStop" to WakeSettingsStore.lastStop(context),
                    ),
                )
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL = "app.wendelin/wake"
    }
}
