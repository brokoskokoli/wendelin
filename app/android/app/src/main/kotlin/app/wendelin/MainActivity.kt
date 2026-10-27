package app.wendelin

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.engine.FlutterEngine

/**
 * The main app (conversation, settings). Most channels come from [WendelinActivity]; the battery
 * and wake-word channels (settings only) are registered here, not in the overlay engine.
 */
class MainActivity : WendelinActivity() {
    private var battery: BatteryChannel? = null
    private var wake: WakeChannel? = null
    private var restricted: RestrictedSettingsChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The visible app may start the wake-word service (WP50, source `app`).
        WakeStarter.sync(this, "app")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        battery = BatteryChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        wake = WakeChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        restricted = RestrictedSettingsChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    // The chat is not visible any more (WP93); Dart reports it again when it is.
    override fun onPause() {
        ChatState.paused()
        super.onPause()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        notify?.handleIntent(intent)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        battery?.dispose()
        battery = null
        wake?.dispose()
        wake = null
        restricted?.dispose()
        restricted = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
