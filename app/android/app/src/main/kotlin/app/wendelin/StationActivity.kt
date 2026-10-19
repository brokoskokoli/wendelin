package app.wendelin

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager

/**
 * The station mode (WP99): a full-screen clock and information display with its own Flutter
 * engine (Dart entrypoint `stationMain`), shown over the lock screen; the device stays locked and
 * the main app stays behind the lock. Started by [StationChannel] (button, voice command) and
 * [StationTileService]; never by itself (no autostart when charging).
 *
 * Nothing ends it but the button „Beenden“ after the keyguard was dismissed ([StationPolicy]):
 * not back, not unplugging, not the screen turning off, not a voice command. The screen is kept
 * on only while Dart asks for it (`FLAG_KEEP_SCREEN_ON`, no wake lock); brightness follows the
 * light sensor without `WRITE_SETTINGS`.
 */
class StationActivity : WendelinActivity(), SensorEventListener {
    private var sensors: SensorManager? = null
    private var ambient = true
    private var lastDark: Boolean? = null

    /** Unplugging is no reason to leave (K63): the receiver only notes it. */
    private val power = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (StationPolicy.endsOn(StationEvent.UNPLUG)) finish()
            VoiceLog.i("station-power ${intent.action} (station stays)")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        StationState.active = true
        // Personal content (appointment titles): no screenshots, hidden in the app switcher.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
        registerReceiver(power, IntentFilter(Intent.ACTION_POWER_DISCONNECTED))
    }

    override fun getDartEntrypointFunctionName(): String = "stationMain"

    // Back does not leave the station: ending asks to unlock.
    @Deprecated("Back never ends the station")
    override fun onBackPressed() {
        if (StationPolicy.endsOn(StationEvent.BACK)) super.onBackPressed()
    }

    override fun onResume() {
        super.onResume()
        sensors = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        sensors?.getDefaultSensor(Sensor.TYPE_LIGHT)?.let {
            sensors?.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL)
        }
    }

    override fun onPause() {
        sensors?.unregisterListener(this)
        super.onPause()
    }

    /** `true`: brightness follows the light sensor; `false`: nearly black (quiet hours). */
    fun setAmbient(on: Boolean) {
        ambient = on
        if (!on) setBrightness(StationPolicy.QUIET_BRIGHTNESS)
    }

    private fun setBrightness(value: Float) {
        val attrs = window.attributes
        attrs.screenBrightness = value
        window.attributes = attrs
    }

    override fun onSensorChanged(event: SensorEvent) {
        val lux = event.values.firstOrNull() ?: return
        if (ambient) setBrightness(StationPolicy.brightnessFor(lux))
        val dark = StationPolicy.isDark(lux)
        if (dark != lastDark) {
            lastDark = dark
            station?.ambient(dark)
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    override fun onDestroy() {
        try {
            unregisterReceiver(power)
        } catch (e: IllegalArgumentException) {
            // Already gone.
        }
        if (isFinishing) StationState.active = false
        super.onDestroy()
    }
}
