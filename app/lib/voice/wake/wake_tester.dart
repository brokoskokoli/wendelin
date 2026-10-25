import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// Outcome of the second stage for one test hit.
enum WakeConfirmation {
  /// Still transcribing.
  pending,

  /// Whisper heard „Wendelin“.
  confirmed,

  /// Whisper did not.
  rejected,

  /// No verifier (Whisper not loaded) or it failed.
  unavailable,
}

/// One candidate in the test mode.
@immutable
final class WakeTestEvent {
  /// Creates an event.
  const WakeTestEvent({
    required this.at,
    required this.similarity,
    required this.speakerId,
    required this.confirmation,
    this.decidedBy,
  });

  /// Position in the stream.
  final Duration at;

  /// Cosine similarity to the speaker's best template.
  final double similarity;

  /// Speaker whose templates fired.
  final String speakerId;

  /// Stage 2.
  final WakeConfirmation confirmation;

  /// `WakeVerifier.kind` of the recognizer that decided stage 2 (`b`,
  /// `parakeet`, `whisper`); `null` while pending or when none decided.
  final String? decidedBy;

  /// A copy with [confirmation] and the verifier that [decidedBy].
  WakeTestEvent withConfirmation(WakeConfirmation c, {String? decidedBy}) =>
      WakeTestEvent(
        at: at,
        similarity: similarity,
        speakerId: speakerId,
        confirmation: c,
        decidedBy: decidedBy,
      );
}

/// „Jetzt ausprobieren“ (WP60): listens, shows every stage-1 candidate
/// (similarity to a personal template over the speaker's threshold) and,
/// separately, whether stage 2 (Whisper) confirmed it. The overlay is not
/// opened. The test always asks Whisper, whatever the production setting
/// says, so the maintainer can judge both stages. Audio stays in a 5 s ring
/// in memory and is never stored.
class WakeTester extends ChangeNotifier {
  /// Creates the tester.
  WakeTester({
    required this.audio,
    required this.features,
    required this.speakers,
    this.verifier,
    this.refractory = const Duration(milliseconds: 1500),
    this.maxEvents = 50,
  });

  /// Microphone.
  final AudioInput audio;

  /// Feature chain.
  final WakeFeatureExtractor features;

  /// Templates of all speakers (each with its threshold).
  final List<WakeTemplates> speakers;

  /// Stage 2; `null` = Whisper not available.
  final WakeVerifier? verifier;

  /// Pause after a candidate.
  final Duration refractory;

  /// Events kept.
  final int maxEvents;

  static const _before = 32000; // 2 s before the hit
  static const _after = 14400; // 0.9 s after it
  static const _ringSize = 5 * 16000;

  final _events = <WakeTestEvent>[];
  final _ring = <int>[];
  final _due = <_Due>[];
  var _lastHit = -1 << 40;
  var _samples = 0;
  var _running = false;
  var _maxSimilarity = -1.0;
  Object? _error;

  /// Candidates, newest last.
  List<WakeTestEvent> get events => List.unmodifiable(_events);

  /// Whether the test listens.
  bool get running => _running;

  /// Highest similarity seen (also below the threshold).
  double get maxSimilarity => _maxSimilarity;

  /// Why it stopped.
  Object? get error => _error;

  /// Listens until [stop].
  Future<void> run() async {
    if (_running) throw StateError('läuft bereits');
    _running = true;
    notifyListeners();
    try {
      await features.open();
      await for (final frame in audio.start()) {
        if (!_running) break;
        await _frame(frame);
      }
    } on Object catch (e) {
      _error = e;
    } finally {
      _running = false;
      await audio.stop();
      await features.close();
      _ring.clear();
      notifyListeners();
    }
  }

  Future<void> _frame(Int16List frame) async {
    _ring.addAll(frame);
    if (_ring.length > _ringSize) {
      _ring.removeRange(0, _ring.length - _ringSize);
    }
    final second = _samples ~/ AudioInput.sampleRate;
    _samples += frame.length;
    for (final w in await features.accept(frame)) {
      _score(w);
    }
    _verifyDue();
    // The similarity readout changes without any event.
    if (_samples ~/ AudioInput.sampleRate != second) notifyListeners();
  }

  void _score(WakeWindow w) {
    for (final t in speakers) {
      if (!t.isCompatible(features.featureVersion, center: features.centerId)) {
        continue;
      }
      final sim = bestSimilarity(
        w.embedding,
        t.embeddings,
        mean: features.embeddingMean,
      );
      if (sim > _maxSimilarity) _maxSimilarity = sim;
      final gap = durationToSamples(refractory);
      if (sim < t.threshold || w.endSample - _lastHit < gap) continue;
      _lastHit = w.endSample;
      final event = WakeTestEvent(
        at: samplesToDuration(w.endSample),
        similarity: sim,
        speakerId: t.speakerId,
        confirmation: verifier == null
            ? WakeConfirmation.unavailable
            : WakeConfirmation.pending,
      );
      _add(event);
      if (verifier != null) _due.add(_Due(event, w.endSample));
    }
  }

  void _add(WakeTestEvent e) {
    _events.add(e);
    if (_events.length > maxEvents) _events.removeAt(0);
    notifyListeners();
  }

  void _verifyDue() {
    final ready = [
      for (final d in _due)
        if (_samples >= d.endSample + _after) d,
    ];
    for (final d in ready) {
      _due.remove(d);
      // Ring index of stream position p: ring.length - (samples - p).
      final end = (_ring.length - (_samples - (d.endSample + _after))).clamp(
        0,
        _ring.length,
      );
      final from = (end - _before - _after).clamp(0, end);
      unawaited(_confirm(d, Int16List.fromList(_ring.sublist(from, end))));
    }
  }

  Future<void> _confirm(_Due d, Int16List pcm) async {
    WakeConfirmation result;
    String? by;
    try {
      result = await verifier!.confirm(pcm)
          ? WakeConfirmation.confirmed
          : WakeConfirmation.rejected;
      // After the call: a preferring verifier names the one that answered.
      by = verifier!.kind;
    } on Object {
      result = WakeConfirmation.unavailable;
    }
    final i = _events.indexOf(d.event);
    if (i < 0) return;
    _events[i] = d.event.withConfirmation(result, decidedBy: by);
    notifyListeners();
  }

  /// Stops listening.
  Future<void> stop() async {
    _running = false;
    await audio.stop();
  }
}

class _Due {
  const _Due(this.event, this.endSample);
  final WakeTestEvent event;
  final int endSample;
}
