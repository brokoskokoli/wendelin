// Gemeinsame Bausteine der Weckwort-Dienst-Tests (wake_host_test.dart,
// wake_host_dev_test.dart).
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:wendelin/platform/wake/wake_detector.dart';
import 'package:wendelin/platform/wake/wake_host.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

const channel = MethodChannel(wakeEngineChannelName);

final class FakeParts implements WakeParts {
  FakeParts({
    this.engineless = false,
    this.verdict = true,
    this.direct = false,
    this.holdMs,
    this.engineError,
    this.openError,
    this.errorsOnlyModel = false,
  });

  /// The errors hit only the classifier (the templates work).
  final bool errorsOnlyModel;

  final bool engineless;
  final bool direct;
  final int? holdMs;
  final Object? engineError;
  final Object? openError;
  bool verdict;
  Object? verifyError;
  int disposed = 0;
  int engines = 0;
  WakeDetector? lastDetector;
  bool? lastStation;
  WakeDetector? verifierDetector;

  @override
  Future<WakeWordEngine?> engine({
    WakeDetector detector = WakeDetector.templates,
    bool station = false,
  }) async {
    engines++;
    lastDetector = detector;
    lastStation = station;
    final hit = !errorsOnlyModel || detector == WakeDetector.model;
    final error = engineError;
    if (hit && error != null) throw error;
    if (hit && openError != null) return OpenFailsEngine(openError!);
    return engineless
        ? null
        : FakeWakeWordEngine(direct: direct, holdMs: holdMs);
  }

  @override
  WakeVerifier verifier({WakeDetector detector = WakeDetector.templates}) {
    verifierDetector = detector;
    return FakeVerifier(
      this,
      detector == WakeDetector.model ? 'parakeet' : 'whisper',
    );
  }

  @override
  Future<void> dispose() async => disposed++;
}

/// An engine whose models cannot be opened (classifier file missing).
final class OpenFailsEngine implements WakeWordEngine {
  OpenFailsEngine(this.error);
  final Object error;

  @override
  Future<void> open(List<KeywordSpec> keywords) async => throw error;

  @override
  Future<List<WakeWordHit>> accept(Int16List frame) async => const [];

  @override
  void reset() {}

  @override
  Future<void> close() async {}
}

final class FakeVerifier implements WakeVerifier {
  FakeVerifier(this.parts, this.kind);
  final FakeParts parts;

  @override
  final String kind;

  @override
  Future<bool> confirm(Int16List pcm) async {
    final e = parts.verifyError;
    if (e != null) throw e;
    return parts.verdict;
  }
}

Uint8List bytes(Int16List frame) =>
    frame.buffer.asUint8List(frame.offsetInBytes, frame.lengthInBytes);
