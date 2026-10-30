package app.wendelin

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform channel for Flutter's [CentralAudioInput] (WP180, ADR 0024).
 *
 * Connects the Flutter UI app ([MainActivity], [AssistantActivity]) to the central
 * audio recording and ring buffer in [WakeWordService].
 */
class CentralAudioChannel(
    private val context: Context,
    messenger: BinaryMessenger,
    private val hubProvider: () -> CentralAudioHub? = { WakeWordService.hub },
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val main = Handler(Looper.getMainLooper())
    private var currentSubscriptionId: String? = null
    private var currentSubscriptionKind: AudioSubscriberKind? = null

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        stopSubscription()
    }

    private fun stopSubscription() {
        val subId = currentSubscriptionId
        if (subId != null) {
            hubProvider()?.unsubscribe(subId)
            currentSubscriptionId = null
            currentSubscriptionKind = null
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> {
                val available = WakeWordService.running && hubProvider() != null
                result.success(available)
            }
            "start" -> {
                val hub = hubProvider()
                if (hub == null || !WakeWordService.running) {
                    result.success(mapOf("started" to false, "reason" to "serviceNotRunning"))
                    return
                }
                WakeWordService.ensureMicRunning()
                val kindArg = call.argument<String>("kind") ?: "session"
                val preRollMs = call.argument<Number>("preRollMs")?.toLong() ?: 0L

                val kind = if (kindArg.equals("enroll", ignoreCase = true)) {
                    AudioSubscriberKind.ENROLL
                } else {
                    AudioSubscriberKind.SESSION
                }

                stopSubscription()

                val preRoll = if (preRollMs > 0L) hub.getPreRollMs(preRollMs) else null
                val subId = hub.subscribe(
                    kind = kind,
                    onChunk = { pcm ->
                        main.post {
                            channel.invokeMethod("audioChunk", mapOf("pcm" to pcm))
                        }
                    },
                    onError = { error ->
                        main.post {
                            channel.invokeMethod("audioError", mapOf("error" to error.javaClass.simpleName))
                        }
                    },
                )
                currentSubscriptionId = subId
                currentSubscriptionKind = kind

                result.success(
                    mapOf(
                        "started" to true,
                        "preRoll" to preRoll,
                    ),
                )
            }
            "stop" -> {
                val kind = call.argument<String>("kind")
                stopSubscription()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL = "app.wendelin/central-audio"
    }
}
