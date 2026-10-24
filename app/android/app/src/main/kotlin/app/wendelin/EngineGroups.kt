package app.wendelin

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * The process-wide [FlutterEngineGroup] (WP145, ADR 0021) for all engines Wendelin starts itself:
 * the headless recognizer and wake word engines ([RecognizerEngine]) and the overlays
 * ([AssistantActivity], [StationActivity]). The main app ([MainActivity]) keeps Flutter's own way.
 * Before, every overlay started a fresh engine in a group of its own and the native heap grew by
 * about 4 MB per opening.
 *
 * Main thread only.
 */
object EngineGroups {
    private var pool: EnginePool<FlutterEngineGroup, FlutterEngine>? = null

    private fun poolFor(app: Context) = pool ?: EnginePool<FlutterEngineGroup, FlutterEngine>(
        newGroup = { FlutterEngineGroup(app) },
        log = { VoiceLog.i(it) },
        destroy = { it.destroy() },
        schedule = { delayMs, block ->
            val main = Handler(Looper.getMainLooper())
            val r = Runnable(block)
            main.postDelayed(r, delayMs)
            EnginePool.Cancelable { main.removeCallbacks(r) }
        },
        onWillDestroy = { engine, callback ->
            engine.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
                override fun onPreEngineRestart() = Unit
                override fun onEngineWillDestroy() = callback()
            })
        },
    ).also { pool = it }

    /** Starts [entrypoint] in an engine of the group and logs where it came from. */
    fun spawn(
        context: Context,
        entrypoint: String,
        tag: String,
        route: String? = null,
        args: List<String>? = null,
        waitForRestoration: Boolean = false,
    ): FlutterEngine {
        val app = context.applicationContext
        // findAppBundlePath() reads the loader's application info, which only exists after
        // startInitialization. FlutterEngineGroup does that in its constructor, but we need the
        // path before the group exists; in release (R8) this was a NullPointerException.
        val loader = FlutterInjector.instance().flutterLoader()
        if (!loader.initialized()) {
            loader.startInitialization(app)
            loader.ensureInitializationComplete(app, null)
        }
        val dart = DartExecutor.DartEntrypoint(loader.findAppBundlePath(), entrypoint)
        val p = poolFor(app)
        val lease = p.obtain { g ->
            g.createAndRunEngine(
                FlutterEngineGroup.Options(app)
                    .setDartEntrypoint(dart)
                    .setInitialRoute(route)
                    .setDartEntrypointArgs(args)
                    .setWaitForRestorationData(waitForRestoration),
            )
        }
        VoiceLog.i(
            "$tag-engine-source group=${if (lease.groupIsNew) "new" else "shared"} " +
                "fromSibling=${lease.fromSibling} siblings=${lease.siblings} live=${p.live}",
        )
        return lease.engine
    }

    /**
     * The overlay's activity ends but Dart still frees native objects (WP145): keep [engine]
     * headless until [release] or [HOLD_MS]. The caller must have left `shouldDestroyEngineWithHost`
     * false by then, else the activity destroys it with itself.
     */
    fun hold(engine: FlutterEngine): Boolean = pool?.hold(engine, HOLD_MS) ?: false

    /** The activity detached [engine]; a timeout that ran before destroys it now. */
    fun cleanedUp(engine: FlutterEngine) = pool?.cleanedUp(engine) ?: Unit

    /** Dart reported its teardown (or the timeout ran): destroys a held engine. */
    fun release(engine: FlutterEngine) = pool?.release(engine) ?: Unit

    /** How long a headless overlay engine may take for its teardown (Dart waits up to 12 s). */
    const val HOLD_MS = 14_000L

    /** The engine for an overlay activity; the activity destroys it with itself unless held. */
    fun forActivity(activity: FlutterActivity, entrypoint: String, tag: String): FlutterEngine =
        spawn(
            activity,
            entrypoint,
            tag,
            route = activity.initialRoute ?: "/",
            args = activity.dartEntrypointArgs,
            waitForRestoration = activity.shouldRestoreAndSaveState(),
        )
}
