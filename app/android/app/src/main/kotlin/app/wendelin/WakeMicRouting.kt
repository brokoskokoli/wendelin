package app.wendelin

import android.content.Context
import android.os.Handler

/**
 * Wiring of the microphone choice and the dialog's phone mode into the wake word service
 * (WP188 parts D and E): the router for the central recording and the controller of the
 * Bluetooth headset in the dialog. The service only tells it when the microphone starts and stops
 * and when the app's voice state changes.
 */
class WakeMicRouting(context: Context, private val main: Handler, private val mic: () -> MicAudioSource?) {
    val router = MicRouter(context)
    private val dialogMic = DialogMicController(DialogMicOps(context, main, router, { mic() != null }, { mic()?.reroute() }))

    /** The recording runs: follow the choice, devices and the dialog without a restart. */
    fun micStarted() {
        router.watch(main) {
            dialogMic.evaluate()
            mic()?.reroute()
        }
        dialogMic.evaluate()
    }

    /** No microphone, no phone mode: also on a conflict, an error and the service stop. */
    fun micStopped() {
        router.unwatch()
        dialogMic.release()
    }

    /** The app's voice state changed (dialog begins or ends). */
    fun appVoiceChanged() = dialogMic.evaluate()
}
