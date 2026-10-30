package app.wendelin

import android.view.WindowManager

/**
 * Manages FLAG_KEEP_SCREEN_ON for AssistantActivity (WP186, K148).
 *
 * Keeps the screen awake during the entire assistant overlay session
 * (command recognition, speech output, follow-up window, undo window),
 * so that Android's lock screen timeout does not turn off the display and
 * terminate the session prematurely via onStop.
 *
 * Android-free callbacks so a JVM unit test can drive it.
 */
class AssistantScreenOn(
    private val addFlags: (Int) -> Unit,
    private val clearFlags: (Int) -> Unit,
) {
    var screenOnHeld: Boolean = false
        private set

    /** Overlay created: keep the screen awake. */
    fun acquire() {
        if (!screenOnHeld) {
            addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            screenOnHeld = true
        }
    }

    /** Overlay closing or destroyed: release screen-on flag. */
    fun release() {
        if (screenOnHeld) {
            clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            screenOnHeld = false
        }
    }
}
