package app.wendelin

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode

/**
 * The assistant overlay: a transparent window with its own Flutter engine running the Dart
 * entrypoint `assistantMain` (app/lib/main.dart), which draws the sheet over the lower part of
 * the screen. Started by [WendelinVoiceSession] via `startAssistantActivity`.
 *
 * Shows over the lock screen; the Dart side then asks to unlock first and shows nothing personal
 * (see ADR 0006). Leaving the overlay (home, screen off) closes it.
 */
class AssistantActivity : WendelinActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
        }
    }

    override fun getDartEntrypointFunctionName(): String = "assistantMain"

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    /** The assistant was invoked again while the overlay is open. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        assistant?.trigger()
    }

    override fun onStop() {
        super.onStop()
        // The overlay belongs to the moment it was opened; it does not stay in the background.
        if (!isChangingConfigurations && assistant?.unlocking != true) finish()
    }
}
