package app.wendelin

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * Platform channel for Flutter's [CentralAudioInput] (WP180, WP184, ADR 0024).
 *
 * Connects the Flutter UI app ([MainActivity], [AssistantActivity]) to the central
 * audio recording and ring buffer in [WakeWordService]. Supports multiple concurrent
 * subscribers identified by unique `subId`.
 */
class CentralAudioChannel(
    private val context: Context?,
    private val channel: MethodChannel,
    private val hubProvider: () -> CentralAudioHub? = { WakeWordService.hub },
    private val isServiceRunning: () -> Boolean = { WakeWordService.running },
    private val ensureMicRunning: () -> Unit = { WakeWordService.ensureMicRunning() },
    private val postToMain: (Runnable) -> Unit = { r ->
        val looper = Looper.getMainLooper()
        if (looper != null && Thread.currentThread() != looper.thread) {
            Handler(looper).post(r)
        } else {
            r.run()
        }
    },
) : MethodChannel.MethodCallHandler {

    constructor(
        context: Context,
        messenger: BinaryMessenger,
        hubProvider: () -> CentralAudioHub? = { WakeWordService.hub },
    ) : this(
        context = context,
        channel = MethodChannel(messenger, CHANNEL),
        hubProvider = hubProvider,
        isServiceRunning = { WakeWordService.running },
        ensureMicRunning = { WakeWordService.ensureMicRunning() },
    )

    private val activeSubIds = ConcurrentHashMap.newKeySet<String>()

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        stopAllSubscriptions()
    }

    private fun stopSubscription(subId: String) {
        if (activeSubIds.remove(subId)) {
            hubProvider()?.unsubscribe(subId)
        }
    }

    private fun stopAllSubscriptions() {
        val hub = hubProvider()
        for (id in activeSubIds) {
            hub?.unsubscribe(id)
        }
        activeSubIds.clear()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> {
                val available = isServiceRunning() && hubProvider() != null
                result.success(available)
            }
            "start" -> {
                val hub = hubProvider()
                if (hub == null || !isServiceRunning()) {
                    result.success(mapOf("started" to false, "reason" to "serviceNotRunning"))
                    return
                }
                ensureMicRunning()
                val subId = call.argument<String>("subId") ?: UUID.randomUUID().toString()
                val kindArg = call.argument<String>("kind") ?: "session"
                val preRollMs = call.argument<Number>("preRollMs")?.toLong() ?: 0L

                val kind = if (kindArg.equals("enroll", ignoreCase = true)) {
                    AudioSubscriberKind.ENROLL
                } else {
                    AudioSubscriberKind.SESSION
                }

                val preRoll = if (preRollMs > 0L) hub.getPreRollMs(preRollMs) else null
                hub.subscribe(
                    kind = kind,
                    id = subId,
                    onChunk = { pcm ->
                        postToMain(Runnable {
                            channel.invokeMethod("audioChunk", mapOf("subId" to subId, "pcm" to pcm))
                        })
                    },
                    onError = { error ->
                        postToMain(Runnable {
                            channel.invokeMethod(
                                "audioError",
                                mapOf("subId" to subId, "error" to error.javaClass.simpleName),
                            )
                        })
                    },
                )
                activeSubIds.add(subId)

                result.success(
                    mapOf(
                        "started" to true,
                        "subId" to subId,
                        "preRoll" to preRoll,
                    ),
                )
            }
            "stop" -> {
                val subId = call.argument<String>("subId")
                @Suppress("UNUSED_VARIABLE")
                val kind = call.argument<String>("kind")
                if (subId != null) {
                    stopSubscription(subId)
                } else {
                    stopAllSubscriptions()
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val CHANNEL = "app.wendelin/central-audio"
    }
}
