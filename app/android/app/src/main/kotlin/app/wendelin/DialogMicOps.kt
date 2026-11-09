package app.wendelin

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler

/**
 * Android side of the dialog's Bluetooth microphone (WP188 part E, logic in [DialogMicController]).
 * Needs only `MODIFY_AUDIO_SETTINGS` (already in the manifest): the audio service checks no other
 * permission for `setMode`, `setCommunicationDevice`, `startBluetoothSco` (AOSP AudioService).
 * Logs types and codes only, never an address.
 */
internal class DialogMicOps(
    context: Context,
    private val main: Handler,
    private val router: MicRouter,
    private val micRunning: () -> Boolean,
    private val reroute: () -> Unit,
) : DialogMicController.Ops {
    private val audio = context.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    override fun dialogActive() = AppVoice.activeWithin(System.currentTimeMillis(), DialogBluetooth.MAX_SILENT_MS)

    override fun micRunning() = micRunning.invoke()

    override fun headsetConnected() = router.dialogHeadset() != null

    override fun enter() {
        val headset = router.dialogHeadset() ?: throw IllegalStateException("no headset")
        OwnCommMode.active = true // before the mode, so the watcher never sees mode 3 as a call
        audio.mode = AudioManager.MODE_IN_COMMUNICATION
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val device = audio.availableCommunicationDevices.firstOrNull { sameDevice(it, headset) }
                ?: throw IllegalStateException("not a communication device")
            if (!audio.setCommunicationDevice(device)) throw IllegalStateException("communication device refused")
        } else {
            @Suppress("DEPRECATION")
            audio.startBluetoothSco()
        }
    }

    override fun leave() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                audio.clearCommunicationDevice()
            } else {
                @Suppress("DEPRECATION")
                audio.stopBluetoothSco()
            }
        } finally {
            try {
                audio.mode = AudioManager.MODE_NORMAL
            } finally {
                OwnCommMode.active = false
            }
        }
    }

    override fun routeChanged() = reroute()

    override fun schedule(delayMs: Long, task: Runnable) {
        main.postDelayed(task, delayMs)
    }

    override fun cancel(task: Runnable) = main.removeCallbacks(task)

    override fun log(line: String) = VoiceLog.i(line + " api=${Build.VERSION.SDK_INT}")

    private fun sameDevice(a: AudioDeviceInfo, b: AudioDeviceInfo) =
        a.type == b.type && a.productName == b.productName && a.address == b.address
}
