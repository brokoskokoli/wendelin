import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/core_providers.dart';
import '../../di/dispose_tracker.dart';
import '../../voice/voice_log.dart';

/// How long the overlay waits for the native frees before it finishes
/// (Android ends the overlay after 1 s anyway, `AssistantChannel.kt`).
const overlayTeardownBudget = Duration(milliseconds: 200);

/// How long the overlay waits for frees that need longer (a Whisper model
/// that is still loading when the overlay closes, seconds): Android is told
/// to wait (`hold`), and the engine only ends when the model is freed, else
/// the model would be loaded in a dead engine and never freed.
const overlayTeardownLongBudget = Duration(seconds: 12);

/// Frees what the overlay engine holds natively (WP145): the overlay ends
/// its engine without disposing the `ProviderContainer`, so no
/// `ref.onDispose` ran and ORT/sherpa sessions, the barge-in chain and the
/// sqlite connection stayed open behind each overlay.
///
/// Disposes [container] (its providers free themselves, see
/// [onDisposeTracked]), waits at most [budget] for the asynchronous frees,
/// then closes the database connection. Nothing may read from [container]
/// afterwards. [hold] asks the host to keep the engine longer when [budget]
/// is not enough; then it waits up to [longBudget]. Never throws.
Future<void> tearDownOverlayEngine(
  ProviderContainer container, {
  Duration budget = overlayTeardownBudget,
  Duration longBudget = overlayTeardownLongBudget,
  Future<void> Function()? hold,
}) async {
  try {
    final tracker = container.read(disposeTrackerProvider);
    final storage = container.read(storageProvider);
    container.dispose();
    final done = (() async {
      await tracker.drain();
      await storage.close();
    })();
    try {
      await done.timeout(budget);
    } on TimeoutException {
      if (hold == null) rethrow;
      voiceLog('overlay-teardown-hold', {'pending': tracker.pending});
      await hold();
      await done.timeout(longBudget);
    }
    voiceLog('overlay-teardown', {'pending': tracker.pending});
  } on TimeoutException {
    voiceLog('overlay-teardown', {'timeout': true});
  } on Object catch (e) {
    voiceLog('overlay-teardown', {'error': e.runtimeType});
  }
}
