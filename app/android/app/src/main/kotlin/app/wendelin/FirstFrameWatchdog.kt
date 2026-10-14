package app.wendelin

/**
 * Closes the assistant overlay when the Flutter engine never draws its first frame (WP56), so
 * the native placeholder does not hang forever. Android-free so a JVM test can drive it.
 */
class FirstFrameWatchdog(
    private val schedule: (delayMs: Long, block: () -> Unit) -> AssistantLauncher.Cancelable,
    private val finish: () -> Unit,
    private val log: (String) -> Unit,
    private val timeoutMs: Long = TIMEOUT_MS,
) {
    private var timer: AssistantLauncher.Cancelable? = null
    private var open = false

    /** The overlay was created: wait for the first frame. */
    fun start() {
        timer?.cancel()
        open = true
        timer = schedule(timeoutMs) { onTimeout() }
    }

    /** The first Flutter frame is shown (or the overlay is gone). */
    fun stop() {
        open = false
        timer?.cancel()
        timer = null
    }

    private fun onTimeout() {
        if (!open) return
        open = false
        log("overlay-first-frame-timeout after=$timeoutMs")
        finish()
    }

    companion object {
        const val TIMEOUT_MS = 10_000L
    }
}
