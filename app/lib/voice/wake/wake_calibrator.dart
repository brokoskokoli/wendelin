import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// Phase of a calibration.
enum CalibrationPhase {
  /// Not started.
  idle,

  /// Listening to the background.
  listening,

  /// Finished; see [WakeCalibrator.result].
  done,

  /// Stopped without a result.
  cancelled,
}

/// Similarity peaks at or above this value count as false-alarm events;
/// lower ones can never reach a usable threshold anyway.
const calibrationEventFloor = 0.5;

/// Highest threshold a calibration stores: positives that resemble each
/// other perfectly (recordings of one voice) would otherwise push the
/// threshold to 1.0, where nothing fires.
const calibrationMaxThreshold = 0.95;

/// A prompt answer needs at least this similarity to count as „said it“.
const calibrationPromptFloor = 0.6;

/// Calibration while the phone lies around (WP60): scores the live windows
/// against the speaker's templates. Only similarity numbers are kept (one
/// peak per 1.5 s slot), never audio, transcripts or embeddings. Now and
/// then [onPrompt] sounds a tone; the best similarity in the following
/// seconds counts as one more positive. The clock is the audio stream, so
/// tests run faster than real time.
class WakeCalibrator extends ChangeNotifier {
  /// Creates the calibrator.
  WakeCalibrator({
    required this.audio,
    required this.features,
    required this.templates,
    required this.store,
    required this.onPrompt,
    this.duration = const Duration(minutes: 30),
    this.firstPrompt = const Duration(minutes: 1),
    this.promptEvery = const Duration(minutes: 3),
    this.minimumEarly = const Duration(minutes: 5),
  });

  /// Microphone.
  final AudioInput audio;

  /// Feature chain.
  final WakeFeatureExtractor features;

  /// Templates being calibrated.
  final WakeTemplates templates;

  /// Where the new threshold is stored.
  final WakeTemplateStore store;

  /// Sounds the tone asking for „Wendelin“.
  final Future<void> Function() onPrompt;

  /// Listening time.
  final Duration duration;

  /// Time of the first prompt.
  final Duration firstPrompt;

  /// Time between prompts.
  final Duration promptEvery;

  /// Shortest listening time [finish] accepts.
  final Duration minimumEarly;

  static const _slot = 24000; // 1.5 s
  static const _toneGap = 8000; // 0.5 s until the speaker starts
  static const _answer = 64000; // 4 s to say it

  var _phase = CalibrationPhase.idle;
  var _samples = 0;
  var _prompts = 0;
  var _answered = 0;
  var _promptStart = -1;
  var _nextPrompt = 0;
  var _excluded = 0; // samples inside prompt windows
  var _slotIndex = -1;
  var _slotMax = -1.0;
  var _slotExcluded = false;
  var _promptMax = -1.0;
  final _negatives = <double>[];
  final _positives = <double>[];
  WakeCalibration? _result;
  Object? _error;
  var _stopped = false;
  var _stored = false;

  /// Current phase.
  CalibrationPhase get phase => _phase;

  /// Time listened so far.
  Duration get elapsed => samplesToDuration(_samples);

  /// Prompts sounded so far.
  int get prompts => _prompts;

  /// Prompts the speaker answered.
  int get answered => _answered;

  /// Result of [run] / [finish]; `meetsTarget == false`: not stored.
  WakeCalibration? get result => _result;

  /// Whether the threshold was stored.
  bool get stored => _stored;

  /// Why it stopped.
  Object? get error => _error;

  /// Whether [finish] may end the run early.
  bool get canFinishEarly =>
      _phase == CalibrationPhase.listening && elapsed >= minimumEarly;

  /// Listens for [duration] (or until [finish] / [cancel]).
  Future<void> run() async {
    if (_phase != CalibrationPhase.idle) throw StateError('läuft bereits');
    _phase = CalibrationPhase.listening;
    _nextPrompt = durationToSamples(firstPrompt);
    notifyListeners();
    try {
      await features.open();
      await for (final frame in audio.start()) {
        await _frame(frame);
        if (_stopped) break;
      }
    } on Object catch (e) {
      _error = e;
    } finally {
      await audio.stop();
      await features.close();
    }
    if (_error != null || _phase != CalibrationPhase.listening) {
      if (_phase == CalibrationPhase.listening) {
        _phase = CalibrationPhase.cancelled;
      }
      notifyListeners();
      return;
    }
    await _conclude();
  }

  Future<void> _frame(Int16List frame) async {
    if (_stopped) return;
    final second = _samples ~/ AudioInput.sampleRate;
    try {
      for (final w in await features.accept(frame)) {
        _window(w);
      }
      _samples += frame.length;
      _schedule();
      if (_samples >= durationToSamples(duration)) _stopped = true;
    } on Object catch (e) {
      _error = e;
      _stopped = true;
    }
    if (_samples ~/ AudioInput.sampleRate != second) notifyListeners();
  }

  void _schedule() {
    if (_promptStart < 0 && _samples >= _nextPrompt) {
      _promptStart = _samples;
      _prompts++;
      _promptMax = -1;
      _nextPrompt = _samples + durationToSamples(promptEvery);
      unawaited(onPrompt().catchError((Object _) {}));
    }
    if (_promptStart >= 0 && _samples >= _promptStart + _toneGap + _answer) {
      if (_promptMax >= calibrationPromptFloor) {
        _positives.add(_promptMax);
        _answered++;
      }
      _excluded += _toneGap + _answer;
      _promptStart = -1;
    }
  }

  void _window(WakeWindow w) {
    final sim = bestSimilarity(w.embedding, templates.embeddings);
    if (_promptStart >= 0 && w.endSample >= _promptStart + _toneGap) {
      if (sim > _promptMax) _promptMax = sim;
    }
    final slot = w.endSample ~/ _slot;
    if (slot != _slotIndex) {
      _closeSlot();
      _slotIndex = slot;
      _slotMax = -1;
      _slotExcluded = false;
    }
    if (_promptStart >= 0) _slotExcluded = true;
    if (sim > _slotMax) _slotMax = sim;
  }

  void _closeSlot() {
    if (!_slotExcluded && _slotMax >= calibrationEventFloor) {
      _negatives.add(_slotMax);
    }
  }

  Future<void> _conclude() async {
    _closeSlot();
    final hours = (_samples - _excluded) / AudioInput.sampleRate / 3600;
    if (hours <= 0) {
      _phase = CalibrationPhase.cancelled;
      notifyListeners();
      return;
    }
    final positives = [
      ...leaveOneOutScores(templates.embeddings),
      ..._positives,
    ];
    var cal = calibrateThreshold(
      positiveScores: positives,
      negativeEvents: _negatives,
      negativeHours: hours,
    );
    if (cal.threshold > calibrationMaxThreshold) {
      // Report the rates of the threshold that is really stored.
      final fa = _negatives.where((n) => n >= calibrationMaxThreshold).length;
      cal = WakeCalibration(
        threshold: calibrationMaxThreshold,
        recall:
            positives.where((p) => p >= calibrationMaxThreshold).length /
            positives.length,
        falseAlarmsPerHour: fa / hours,
        meetsTarget: cal.meetsTarget && fa / hours <= 1,
      );
    }
    _result = cal;
    if (cal.meetsTarget) {
      await store.save(templates.withThreshold(cal.threshold));
      _stored = true;
    }
    _phase = CalibrationPhase.done;
    notifyListeners();
  }

  /// Ends the run with what was heard so far (see [canFinishEarly]).
  void finish() {
    if (canFinishEarly) _stopped = true;
  }

  /// Stops without a result.
  Future<void> cancel() async {
    _phase = CalibrationPhase.cancelled;
    _stopped = true;
    await audio.stop();
  }
}
