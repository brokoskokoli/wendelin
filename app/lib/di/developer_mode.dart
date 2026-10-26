import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../voice/dev_log.dart';
import 'app_settings.dart';
import 'providers.dart';

/// Whether the developer mode is on (WP148): extended logging with content
/// (`Wendelin/dev`) and the developer options in the settings.
final developerModeProvider = NotifierProvider<DeveloperModePref, bool>(
  DeveloperModePref.new,
);

/// Reads the stored developer mode into [devLogEnabled] (WP148).
///
/// Called when a voice session or a request starts, so a switch made in
/// another engine (the app, while the overlay or the station runs) works
/// without a restart. A read error counts as off (fail-closed).
Future<void> refreshDevLogFlag(Ref ref) async {
  try {
    devLogEnabled =
        await ref
            .read(storageProvider)
            .settings
            .get(AppSettings.developerMode) ??
        false;
  } on Object {
    devLogEnabled = false;
  }
}

/// Hooks a voice pipeline into the developer log (WP148): content events
/// (`stt-reject`, `wake-strip`) go to [devLog], and the stored flag is read
/// again, so a switch made in another engine counts for this session. The
/// read finishes long before the first text exists (recording comes first).
extension DevLogPipeline on VoicePipeline {
  /// Hooks this pipeline up and returns it.
  VoicePipeline withDevLog(Ref ref) {
    contentLog = devLog;
    unawaited(refreshDevLogFlag(ref));
    return this;
  }
}

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
