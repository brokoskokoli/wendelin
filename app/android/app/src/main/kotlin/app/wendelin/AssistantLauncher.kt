package app.wendelin

/**
 * What one assistant invocation does after the system shows the session (B10), without Android
 * types so a JVM test can drive it:
 *
 * 1. Start the overlay ([start], `startAssistantActivity` with a fresh intent).
 * 2. Wait until the [AssistantActivity] reports that it was created or got the new intent
 *    ([onArrived]); then end the session ([end], `finish()`), so no hidden session stays behind.
 * 3. If the start throws, or nothing arrives within [confirmTimeoutMs], start once more with a
 *    fresh intent; if that fails too, log it and end the session.
 *
 * Every step is logged without content ([log], tag `Wendelin/voice`).
 */
class AssistantLauncher(
    private val start: () -> Unit,
    private val schedule: (delayMs: Long, block: () -> Unit) -> Cancelable,
    private val end: () -> Unit,
    private val log: (String) -> Unit,
    private val confirmTimeoutMs: Long = CONFIRM_TIMEOUT_MS,
) {
    /** A scheduled block that can be dropped. */
    fun interface Cancelable {
        fun cancel()
    }

    private var attempt = 0
    private var waiting: Cancelable? = null
    private var done = true

    /** Whether the session waits for the overlay. */
    val pending: Boolean get() = !done

    /** The system showed the session (again): start the overlay. */
    fun onShow(showFlags: Int) {
        log("session-show flags=$showFlags")
        waiting?.cancel()
        attempt = 0
        done = false
        launch()
    }

    private fun launch() {
        attempt++
        try {
            start()
            log("assistant-start attempt=$attempt result=ok")
        } catch (e: Exception) {
            log("assistant-start attempt=$attempt result=error error=${e.javaClass.simpleName}")
            if (attempt < MAX_ATTEMPTS) return launch()
            return finish("start-error")
        }
        waiting = schedule(confirmTimeoutMs) { onTimeout() }
    }

    private fun onTimeout() {
        if (done) return
        log("assistant-start attempt=$attempt result=missing after=$confirmTimeoutMs")
        if (attempt < MAX_ATTEMPTS) launch() else finish("missing")
    }

    /** The overlay activity was created or received the new intent. */
    fun onArrived() {
        if (done) return
        finish("arrived")
    }

    /** The system hid the session (e.g. another app came up). */
    fun onHide() {
        log("session-hide pending=${!done}")
        if (!done) finish("hidden")
    }

    private fun finish(reason: String) {
        waiting?.cancel()
        waiting = null
        done = true
        log("session-finish reason=$reason attempts=$attempt")
        end()
    }

    companion object {
        /** How long the session waits for the overlay before it starts it again. */
        const val CONFIRM_TIMEOUT_MS = 3000L

        /** First start plus one retry. */
        const val MAX_ATTEMPTS = 2
    }
}

/**
 * Process-wide link from [AssistantActivity] to the session that started it: the activity
 * reports [arrived], the waiting [AssistantLauncher] ends its session.
 */
object AssistantArrivals {
    private var listener: (() -> Unit)? = null

    /** Registers the launcher waiting for the overlay (replaces an older one). */
    fun await(onArrived: () -> Unit) {
        listener = onArrived
    }

    /** Drops [onArrived] if it is still the registered one. */
    fun clear(onArrived: () -> Unit) {
        if (listener === onArrived) listener = null
    }

    /** The overlay activity was created or got a new intent. */
    fun arrived() {
        val l = listener
        listener = null
        l?.invoke()
    }
}
