package app.wendelin

import android.app.Notification
import android.content.Context

/**
 * WP171: whether stage 2 cannot decide (reason as sent by the engine: no model, or no
 * sequences). The listening notification says so; [onReport] rebuilds it.
 */
internal class WakeGapState(private val context: Context, private val listening: () -> Boolean) {
    private var reason: String? = null

    /** The "listening" notification, with the notice if there is a gap. */
    fun notification(): Notification = WakeNotifications.listening(context, gap = reason)

    /** The engine found out (or no longer finds) that stage 2 has a gap: rebuild the notification. */
    fun onReport(reported: String?) {
        val gap = if (WakePolicy.stage2GapActive(reported)) reported else null
        if (gap == reason) return
        reason = gap
        VoiceLog.i("wake-gap reason=${gap ?: "none"}")
        // Only while listening: a pause shows its own notification.
        if (listening()) WakeNotifications.update(context, notification())
    }

    /** The service ends: the next start asks the engine again. */
    fun reset() {
        reason = null
    }
}
