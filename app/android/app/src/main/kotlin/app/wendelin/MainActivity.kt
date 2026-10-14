package app.wendelin

import io.flutter.embedding.engine.FlutterEngine

/**
 * The main app (conversation, settings). Most channels come from [WendelinActivity]; the battery
 * channel (settings only) is registered here, not in the overlay engine.
 */
class MainActivity : WendelinActivity() {
    private var battery: BatteryChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        battery = BatteryChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        battery?.dispose()
        battery = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
