package app.wendelin

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The notifications of the wake-word service (WP50): the permanent one while it listens or is
 * paused (own quiet channel, buttons „Pause 1 h“ and „Aus“) and the hint „Wieder einschalten“
 * after it ended without the user's wish. No content of any kind.
 */
object WakeNotifications {
    const val CHANNEL_ID = "wake-word"
    const val ID_SERVICE = 4801
    private const val ID_REENABLE = 4802

    private fun manager(context: Context) =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun ensureChannel(context: Context) {
        manager(context).createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Wake Word", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Zeigt, dass Wendelin auf „Wendelin“ hört."
                setShowBadge(false)
            },
        )
    }

    private fun action(context: Context, action: String, source: String? = null, foreground: Boolean = false): PendingIntent {
        val intent = Intent(context, WakeWordService::class.java).setAction(action)
        source?.let { intent.putExtra(WakeWordService.EXTRA_SOURCE, it) }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return if (foreground) {
            PendingIntent.getForegroundService(context, action.hashCode(), intent, flags)
        } else {
            PendingIntent.getService(context, action.hashCode(), intent, flags)
        }
    }

    private fun openApp(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        0,
        Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun builder(context: Context, title: String, text: String): Notification.Builder {
        ensureChannel(context)
        return Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_wendelin)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(openApp(context))
            .setOnlyAlertOnce(true)
    }

    private fun act(context: Context, label: String, pi: PendingIntent) =
        Notification.Action.Builder(null, label, pi).build()

    /** Permanent notification while listening; [note] names a pause by a conflict. */
    fun listening(context: Context, note: String? = null): Notification =
        builder(
            context,
            "Wendelin hört auf „Wendelin“",
            note ?: "Das Mikrofon ist an. Audio bleibt auf dem Gerät.",
        )
            .setOngoing(true)
            .addAction(act(context, "Pause 1 h", action(context, WakeWordService.ACTION_PAUSE)))
            .addAction(act(context, "Aus", action(context, WakeWordService.ACTION_OFF)))
            .build()

    /** Permanent notification during „Pause 1 h“. */
    fun paused(context: Context, untilMs: Long): Notification {
        val time = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(untilMs))
        return builder(context, "Wendelin pausiert", "Bis $time Uhr, das Mikrofon ist frei.")
            .setOngoing(true)
            .addAction(act(context, "Fortsetzen", action(context, WakeWordService.ACTION_RESUME)))
            .addAction(act(context, "Aus", action(context, WakeWordService.ACTION_OFF)))
            .build()
    }

    /** „Wieder einschalten“ after the service ended on its own ([withAction]: it can restart). */
    fun showReenable(context: Context, text: String, withAction: Boolean) {
        val b = builder(context, "Wake Word ist aus", text).setAutoCancel(true)
        if (withAction) {
            b.addAction(
                act(
                    context,
                    "Wieder einschalten",
                    action(context, WakeWordService.ACTION_START, "notif", foreground = true),
                ),
            )
        }
        manager(context).notify(ID_REENABLE, b.build())
    }

    fun clearReenable(context: Context) = manager(context).cancel(ID_REENABLE)

    fun update(context: Context, notification: Notification) =
        manager(context).notify(ID_SERVICE, notification)
}
