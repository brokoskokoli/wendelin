package app.wendelin

import android.content.Context
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform side of `ChannelTorchPort` (app/lib/platform/channel_torch_port.dart): flash LED as a
 * flashlight via `CameraManager.setTorchMode`. Needs no CAMERA permission. The state comes from a
 * `TorchCallback`, so it also follows the system tile.
 */
class TorchChannel(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val manager =
        context.applicationContext.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    private val cameraId: String? = findFlashCamera()
    private var on = false

    private val callback = object : CameraManager.TorchCallback() {
        override fun onTorchModeChanged(id: String, enabled: Boolean) {
            if (id == cameraId) on = enabled
        }

        override fun onTorchModeUnavailable(id: String) {
            if (id == cameraId) on = false
        }
    }

    init {
        channel.setMethodCallHandler(this)
        if (cameraId != null) manager.registerTorchCallback(callback, Handler(Looper.getMainLooper()))
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        manager.unregisterTorchCallback(callback)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(cameraId != null)
            "state" -> result.success(on)
            "set" -> set(call.argument<Boolean>("on"), result)
            else -> result.notImplemented()
        }
    }

    private fun set(enabled: Boolean?, result: MethodChannel.Result) {
        val id = cameraId
        when {
            enabled == null -> result.error("bad_args", "on fehlt", null)
            id == null -> result.error("no_led", "Keine Blitz-LED", null)
            else ->
                try {
                    manager.setTorchMode(id, enabled)
                    // The callback follows later; report the new state right away.
                    on = enabled
                    result.success(null)
                } catch (e: CameraAccessException) {
                    val code = when (e.reason) {
                        CameraAccessException.CAMERA_IN_USE,
                        CameraAccessException.MAX_CAMERAS_IN_USE -> "camera_in_use"
                        else -> "unavailable"
                    }
                    result.error(code, "Taschenlampe nicht nutzbar", null)
                } catch (_: IllegalArgumentException) {
                    result.error("no_led", "Keine Blitz-LED", null)
                }
        }
    }

    private fun findFlashCamera(): String? =
        try {
            manager.cameraIdList.firstOrNull {
                val c = manager.getCameraCharacteristics(it)
                c.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true &&
                    c.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
            }
        } catch (_: CameraAccessException) {
            null
        }

    companion object {
        const val CHANNEL = "app.wendelin/torch"
    }
}
