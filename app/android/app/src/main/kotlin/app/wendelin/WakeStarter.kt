package app.wendelin

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.BatteryManager
import android.os.Build

/**
 * Starts and stops [WakeWordService] from the places that may do so (WP50): the visible app
 * (`app`), `WendelinVoiceInteractionService.onReady` (`vis`), the charging events (`charge`,
 * `unplug`) and the notification (`notif`). No `BOOT_COMPLETED`: after a restart only the
 * assistant role brings the service back. Every refusal is logged with its reason
 * (`wake-start result=…`, [WakePolicy]).
 */
object WakeStarter {
    /** The start/stop decision with the live state of the device (also used by [WakeWordService]). */
    fun decide(context: Context, settings: WakeSettings): WakeDecision = WakePolicy.decide(
        settings,
        holdsRole = RecognizerSwitch.holdsAssistantRole(context),
        micGranted = micGranted(context),
        charging = isCharging(context),
        nowMs = System.currentTimeMillis(),
        station = StationState.open,
        stationModelInstalled = WakePolicy.classifierInstalled(context.filesDir),
    )

    fun sync(context: Context, source: String) {
        val settings = WakeSettingsStore.load(context)
        val decision = decide(context, settings)
        when (decision) {
            WakeDecision.Start -> start(context, source)
            is WakeDecision.Skip -> {
                VoiceLog.i("wake-start result=${decision.reason} source=$source")
                // A pause is the service's own business; everything else ends it.
                if (WakeWordService.running && decision.reason != "paused") {
                    send(context, WakeWordService.ACTION_STOP, source, decision.reason)
                }
                if (settings.enabled && decision.reason == "no-role") {
                    WakeNotifications.showReenable(
                        context,
                        WakeTexts.load(context).noRole,
                        withAction = false,
                    )
                }
            }
        }
    }

    fun start(context: Context, source: String) {
        try {
            WakeNotifications.clearReenable(context)
            context.startForegroundService(intent(context, WakeWordService.ACTION_START, source))
        } catch (e: Exception) {
            VoiceLog.i("wake-start result=denied source=$source error=${e.javaClass.simpleName}")
        }
    }

    private fun send(context: Context, action: String, source: String, reason: String?) {
        try {
            context.startForegroundService(intent(context, action, source).putExtra(WakeWordService.EXTRA_REASON, reason))
        } catch (e: Exception) {
            VoiceLog.i("wake-stop result=denied source=$source error=${e.javaClass.simpleName}")
        }
    }

    private fun intent(context: Context, action: String, source: String) =
        Intent(context, WakeWordService::class.java)
            .setAction(action)
            .putExtra(WakeWordService.EXTRA_SOURCE, source)

    fun micGranted(context: Context): Boolean =
        context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    fun isCharging(context: Context): Boolean {
        val status = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        return (status?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0
    }

    /** Minimum Android for the microphone service type (API 29). */
    val hasServiceType: Boolean get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
}
