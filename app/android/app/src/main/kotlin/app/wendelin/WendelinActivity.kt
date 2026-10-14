package app.wendelin

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Flutter activity with Wendelin's platform channels (calendar, files, vault, apps, network,
 * OAuth login, assistant).
 * Both the main app ([MainActivity]) and the assistant overlay ([AssistantActivity]) run
 * the tools, so both engines need the same channels.
 */
abstract class WendelinActivity : FlutterActivity() {
    private var calendar: CalendarChannel? = null
    private var files: FilesChannel? = null
    private var vault: VaultChannel? = null
    private var window: WindowChannel? = null
    private var apps: AppsChannel? = null
    private var network: NetworkChannel? = null
    private var auth: AuthChannel? = null
    private var torch: TorchChannel? = null
    protected var assistant: AssistantChannel? = null
        private set

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Assistant role may have changed while the app was not running.
        RecognizerSwitch.sync(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        calendar = CalendarChannel(this, messenger)
        files = FilesChannel(this, messenger)
        vault = VaultChannel(this, messenger)
        window = WindowChannel(this, messenger)
        apps = AppsChannel(this, messenger)
        network = NetworkChannel(this, messenger)
        auth = AuthChannel(this, messenger)
        torch = TorchChannel(this, messenger)
        assistant = AssistantChannel(this, messenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        calendar?.dispose()
        calendar = null
        files?.dispose()
        files = null
        vault?.dispose()
        vault = null
        window?.dispose()
        window = null
        apps?.dispose()
        apps = null
        network?.dispose()
        network = null
        auth?.dispose()
        auth = null
        torch?.dispose()
        torch = null
        assistant?.dispose()
        assistant = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onPause() {
        super.onPause()
        auth?.onPause()
    }

    override fun onResume() {
        super.onResume()
        auth?.onResume()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        calendar?.onPermissionResult(requestCode, grantResults)
    }

    @Deprecated("Activity result API of FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (files?.onActivityResult(requestCode, resultCode, data) == true) return
        if (vault?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }
}
