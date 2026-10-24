package app.wendelin

import android.content.Context
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
        val dart = DartExecutor.DartEntrypoint(
            FlutterInjector.instance().flutterLoader().findAppBundlePath(),
            entrypoint,
        )
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

    /** The engine for an overlay activity; the activity destroys it with itself. */
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
