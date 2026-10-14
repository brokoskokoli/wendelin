import 'package:flutter/widgets.dart';

/// Releases the microphone when the app leaves the foreground (WP60): the
/// enrollment, calibration and test screens must never keep listening in the
/// background.
mixin WakeBackgroundAbort<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  /// Stops the microphone work of the screen.
  Future<void> abortForBackground();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      abortForBackground();
    }
  }
}
