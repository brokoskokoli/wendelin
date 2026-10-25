package app.wendelin

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Headless Flutter engine running `recognizerMain` (app/lib/main.dart) for
 * [WendelinRecognitionService] (ADR 0008): Silero VAD, the pipeline's endpointing and Whisper
 * in Dart, without UI, database or agent. Calls to Dart wait until it reported `ready`.
 * [WakeWordService] (WP50) runs `wakeWordMain` on its own channel the same way.
 *
 * Main thread only.
 */
class RecognizerEngine(
    context: Context,
    private val handler: (MethodCall) -> Unit,
    entrypoint: String = "recognizerMain",
    channelName: String = CHANNEL,
) {
    // Spawned from the process-wide group (WP145): shares resources with the overlays' engines.
    private val engine = EngineGroups.spawn(context, entrypoint, "recognizer")
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, channelName)
    private val pending = mutableListOf<Pair<String, Any?>>()
    private val main = Handler(Looper.getMainLooper())
    private var ready = false
    private var destroyed = false

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "ready") {
                ready = true
                pending.forEach { (method, args) -> channel.invokeMethod(method, args) }
                pending.clear()
            } else {
                handler(call)
            }
            result.success(null)
        }
    }

    /** Whether Dart has started and answers. */
    val isReady: Boolean get() = ready

    /** Sends [method] to Dart (queued until it is ready). */
    fun send(method: String, args: Any?) {
        if (destroyed) return
        if (ready) channel.invokeMethod(method, args) else pending.add(method to args)
    }

    /** Frees Whisper in Dart (`shutdown`), then destroys the engine (at most after 2 s). */
    fun destroy() {
        if (destroyed) return
        destroyed = true
        pending.clear()
        var done = false
        val finish = Runnable {
            if (!done) {
                done = true
                channel.setMethodCallHandler(null)
                engine.destroy()
            }
        }
        if (!ready) {
            finish.run()
            return
        }
        main.postDelayed(finish, SHUTDOWN_TIMEOUT_MS)
        channel.invokeMethod("shutdown", null, object : MethodChannel.Result {
            override fun success(result: Any?) = finish.run()
            override fun error(code: String, message: String?, details: Any?) = finish.run()
            override fun notImplemented() = finish.run()
        })
    }

    companion object {
        const val CHANNEL = "app.wendelin/recognizer"
        private const val SHUTDOWN_TIMEOUT_MS = 2000L
    }
}
