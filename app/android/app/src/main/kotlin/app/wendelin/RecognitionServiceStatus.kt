package app.wendelin

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer

/**
 * Which speech recognizer Android gives other apps (B12, ADR 0008): the secure setting
 * `voice_recognition_service`. It follows the assistant role on AOSP; on devices with Google
 * services (e.g. HyperOS) it often stays with Google and cannot be changed there. Wendelin only
 * reads it and never changes it (no `WRITE_SECURE_SETTINGS`).
 *
 * Result for the channel: `{state: active | inactive | other | unknown, appName?}`.
 */
object RecognitionServiceStatus {
    const val ACTIVE = "active"

    /** The setting names Wendelin, but its service is off (no assistant role or not offered). */
    const val INACTIVE = "inactive"
    const val OTHER = "other"
    const val UNKNOWN = "unknown"

    /** Secure setting with the default `RecognitionService` (`package/class`). */
    const val SETTING = "voice_recognition_service"

    private const val SELF_TEST_TIMEOUT_MS = 2000L

    /** Outcome of [evaluate]: the state and, for [OTHER], the package of that service. */
    data class Evaluation(val state: String, val otherPackage: String? = null)

    /**
     * Package and fully qualified class of a flattened component (`pkg/.Cls` or `pkg/pkg.Cls`,
     * like `ComponentName.unflattenFromString`), or `null` if [flat] is none.
     */
    fun parseComponent(flat: String?): Pair<String, String>? {
        val value = flat?.trim().orEmpty()
        val slash = value.indexOf('/')
        if (slash <= 0 || slash == value.length - 1) return null
        val pkg = value.substring(0, slash)
        val rest = value.substring(slash + 1)
        if ('/' in rest) return null
        return pkg to if (rest.startsWith(".")) pkg + rest else rest
    }

    /**
     * Compares the setting [value] with Wendelin's own recognizer component. Pointing to
     * Wendelin is only [ACTIVE] while the service may answer ([serviceActive],
     * [RecognizerSwitch.isActive]); otherwise other apps get errors: [INACTIVE].
     */
    fun evaluate(
        value: String?,
        ownPackage: String,
        ownClass: String,
        serviceActive: Boolean,
    ): Evaluation {
        val (pkg, cls) = parseComponent(value) ?: return Evaluation(UNKNOWN)
        return when {
            pkg != ownPackage || cls != ownClass -> Evaluation(OTHER, pkg)
            serviceActive -> Evaluation(ACTIVE)
            else -> Evaluation(INACTIVE)
        }
    }

    /** Delayed tasks: the main looper in the app, a fake in JVM tests. */
    interface Scheduler {
        fun post(delayMs: Long, task: Runnable)
        fun cancel(task: Runnable)
    }

    /**
     * One self-test run: answers exactly once, with the result or [UNKNOWN] after [timeoutMs].
     * Every run has its own timeout task, so parallel runs never cancel each other's timeout.
     */
    class OnceWithTimeout(
        private val scheduler: Scheduler,
        timeoutMs: Long,
        private val onDone: (Evaluation) -> Unit,
    ) {
        private var finished = false
        private val timeout = Runnable { finish(Evaluation(UNKNOWN)) }

        init {
            scheduler.post(timeoutMs, timeout)
        }

        fun finish(evaluation: Evaluation) {
            if (finished) return
            finished = true
            scheduler.cancel(timeout)
            onDone(evaluation)
        }
    }

    /** Channel answer for [evaluation] with the app name of another service. */
    fun toArgs(evaluation: Evaluation, appName: String?): Map<String, Any?> =
        if (evaluation.state == OTHER) {
            mapOf("state" to OTHER, "appName" to appName)
        } else {
            mapOf("state" to evaluation.state)
        }

    /**
     * Reads the state and answers on the main thread. If the setting cannot be read, a short
     * self-test without microphone asks the default recognizer whether it supports a request
     * ([SpeechRecognizer.checkRecognitionSupport], Android 13+): if [WendelinRecognitionService]
     * answers, it is the system recognizer; any other answer means another service. Without
     * that API, on a timeout or an error the state stays unknown.
     */
    fun read(context: Context, answer: (Map<String, Any?>) -> Unit) {
        val value = try {
            Settings.Secure.getString(context.contentResolver, SETTING)
        } catch (e: SecurityException) {
            null
        }
        val evaluation = evaluate(
            value,
            context.packageName,
            WendelinRecognitionService::class.java.name,
            RecognizerSwitch.isActive(context),
        )
        if (evaluation.state != UNKNOWN) {
            answer(toArgs(evaluation, evaluation.otherPackage?.let { appLabel(context, it) }))
            return
        }
        selfTest(context) { answer(toArgs(it, null)) }
    }

    /** App name of [pkg] (visible through the `RecognitionService` query), else the package. */
    private fun appLabel(context: Context, pkg: String): String = try {
        val pm = context.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (e: PackageManager.NameNotFoundException) {
        pkg
    }

    private fun selfTest(context: Context, done: (Evaluation) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            !SpeechRecognizer.isRecognitionAvailable(context)
        ) {
            done(Evaluation(UNKNOWN))
            return
        }
        val main = Handler(Looper.getMainLooper())
        var recognizer: SpeechRecognizer? = null
        val startedAt = System.nanoTime()
        val run = OnceWithTimeout(
            object : Scheduler {
                override fun post(delayMs: Long, task: Runnable) {
                    main.postDelayed(task, delayMs)
                }

                override fun cancel(task: Runnable) = main.removeCallbacks(task)
            },
            SELF_TEST_TIMEOUT_MS,
        ) {
            recognizer?.destroy()
            done(it)
        }
        fun finish(evaluation: Evaluation) = run.finish(evaluation)
        try {
            val created = SpeechRecognizer.createSpeechRecognizer(context)
            recognizer = created
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            val answered = {
                main.post {
                    finish(
                        if (WendelinRecognitionService.supportCheckedSince(startedAt)) {
                            Evaluation(ACTIVE)
                        } else {
                            Evaluation(OTHER)
                        },
                    )
                }
            }
            created.checkRecognitionSupport(
                intent,
                context.mainExecutor,
                object : RecognitionSupportCallback {
                    override fun onSupportResult(support: RecognitionSupport) {
                        answered()
                    }

                    override fun onError(error: Int) {
                        // Not bound at all: nothing is known about the default service.
                        if (error == SpeechRecognizer.ERROR_CLIENT ||
                            error == SpeechRecognizer.ERROR_SERVER_DISCONNECTED
                        ) {
                            main.post { finish(Evaluation(UNKNOWN)) }
                        } else {
                            answered()
                        }
                    }
                },
            )
        } catch (e: RuntimeException) {
            finish(Evaluation(UNKNOWN))
        }
    }
}
