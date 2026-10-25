import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../voice/dev_log.dart';
import 'app_settings.dart';
import 'providers.dart';

/// Whether the developer mode is on (WP148): extended logging with content
/// (`Wendelin/dev`) and the developer options in the settings.
final developerModeProvider = NotifierProvider<DeveloperModePref, bool>(
  DeveloperModePref.new,
);

/// Developer mode preference; also drives [devLogEnabled].
final class DeveloperModePref extends Notifier<bool> {
  @override
  bool build() {
    final on = ref.watch(startupProvider).developerMode;
    devLogEnabled = on;
    return on;
  }

  /// Switches the mode and stores it.
  Future<void> set({required bool enabled}) async {
    state = enabled;
    devLogEnabled = enabled;
    await ref
        .read(storageProvider)
        .settings
        .set(AppSettings.developerMode, enabled);
  }
}
