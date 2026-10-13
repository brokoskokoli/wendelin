package app.wendelin

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Flutter activity with Wendelin's platform channels (calendar, files, vault, assistant).
 * Both the main app ([MainActivity]) and the assistant overlay ([AssistantActivity]) run
 * the tools, so both engines need the same channels.
 */
abstract class WendelinActivity : FlutterActivity() {
    private var calendar: CalendarChannel? = null
    private var files: FilesChannel? = null
    private var vault: VaultChannel? = null
    protected var assistant: AssistantChannel? = null
        private set

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        calendar = CalendarChannel(this, messenger)
        files = FilesChannel(this, messenger)
        vault = VaultChannel(this, messenger)
        assistant = AssistantChannel(this, messenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        calendar?.dispose()
        calendar = null
        files?.dispose()
        files = null
        vault?.dispose()
        vault = null
        assistant?.dispose()
        assistant = null
        super.cleanUpFlutterEngine(flutterEngine)
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
