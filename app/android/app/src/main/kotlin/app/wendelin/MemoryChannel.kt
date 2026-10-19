package app.wendelin

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Pushes Android's `onTrimMemory` level to Dart (WP103, app/lib/platform/channel_memory_trim.dart),
 * so the loaded recognizer and voice models are freed under memory pressure even when
 * „Modell im Speicher halten“ is on. No permission needed.
 */
class MemoryChannel(messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, CHANNEL)

    /** [level] is one of the `ComponentCallbacks2.TRIM_MEMORY_*` constants. */
    fun trim(level: Int) {
        channel.invokeMethod("trim", level)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    companion object {
        const val CHANNEL = "app.wendelin/memory"
    }
}
