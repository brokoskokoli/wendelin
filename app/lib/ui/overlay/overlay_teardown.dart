import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/core_providers.dart';
import '../../di/dispose_tracker.dart';
import '../../voice/voice_log.dart';

/// How long the overlay waits for the native frees, also a Whisper model
/// that is still loading when the overlay closes (seconds). The host is
/// released before (`AssistantPlatform.releaseHost`) and keeps the engine
/// headless for 14 s (`AssistantChannel.kt`), so nothing waits for this.
const overlayTeardownBudget = Duration(seconds: 12);

/// Frees what the overlay engine holds natively (WP145): the overlay ends
/// its engine without disposing the `ProviderContainer`, so no
/// `ref.onDispose` ran and ORT/sherpa sessions, the barge-in chain and the
/// sqlite connection stayed open behind each overlay.
///
/// Disposes [container] (its providers free themselves, see
/// [onDisposeTracked]), waits at most [budget] for the asynchronous frees,
/// then closes the database connection. Nothing may read from [container]
/// afterwards. Never throws.
Future<void> tearDownOverlayEngine(
  ProviderContainer container, {
  Duration budget = overlayTeardownBudget,
}) async {
  try {
    final tracker = container.read(disposeTrackerProvider);
    final storage = container.read(storageProvider);
    tracker.markEnding();
    container.dispose();
    await (() async {
      await tracker.drain();
      // Writes the database client had already sent are processed before
      // the close (one ordered connection per client); later ones cannot
      // start: they would need a provider of the disposed container.
      await storage.close();
    })().timeout(budget);
    voiceLog('overlay-teardown', {'pending': tracker.pending});
  } on TimeoutException {
    voiceLog('overlay-teardown', {'timeout': true});
  } on Object catch (e) {
    voiceLog('overlay-teardown', {'error': e.runtimeType});
  }
}
