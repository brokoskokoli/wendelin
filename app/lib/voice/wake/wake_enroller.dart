import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'utterance_capture.dart';

/// Where in the padded recording the template window is taken: this long
/// after the end of the word (the stream position the classifier window
/// reaches while the word was just spoken, measured in WP44).
const templateOffset = Duration(milliseconds: 300);

/// Embedding window of one spoken word: [pcm] is padded with silence on
/// both sides, run through a fresh stream of [features] and the window
/// whose end lies [templateOffset] after [speechEnd] is returned (`null`
/// if the models yield no window). The audio is not kept.
Future<Float32List?> embedUtterance(
  WakeFeatureExtractor features,
  Int16List pcm,
  int speechEnd,
) async {
  const lead = AudioInput.sampleRate; // 1 s
  const trail = 2 * AudioInput.sampleRate;
  features.reset();
  final padded = Int16List(lead + pcm.length + trail)
    ..setRange(lead, lead + pcm.length, pcm);
  final target = lead + speechEnd + durationToSamples(templateOffset);
  WakeWindow? best;
  for (var i = 0; i < padded.length; i += 1280) {
    final end = i + 1280 > padded.length ? padded.length : i + 1280;
    for (final w in await features.accept(
      Int16List.sublistView(padded, i, end),
    )) {
      if (best == null ||
          (w.endSample - target).abs() < (best.endSample - target).abs()) {
        best = w;
      }
    }
  }
  features.reset();
  return best?.embedding;
}

/// The microphone stream ended before the enrollment was done.
final class MicrophoneEnded implements Exception {
  /// Creates the exception.
  const MicrophoneEnded();

  @override
  String toString() => 'Das Mikrofon hat aufgehört zu liefern.';
}

/// Provisional threshold right after the enrollment, before the calibration
/// has seen any background: the floor of `calibrateThreshold` (WP44
/// measurement: about 84 % recall at 2.8 candidates per hour, stage 2 filters
/// the rest). Recordings of one voice can be nearly identical (leave-one-out
/// similarity 1.0); a threshold derived from them would never fire on a live
/// utterance.
const wakeProvisionalThreshold = wakeMinThreshold;

/// Provisional threshold of „Stopp“ (WP64b): a short word is confused with
/// other speech more easily, so it starts stricter than „Wendelin“.
const stopProvisionalThreshold = 0.9;

/// Phase of an enrollment.
enum EnrollPhase {
  /// Not started.
  idle,

  /// Waiting for the next „Wendelin“.
  listening,

  /// Computing the embedding of a recording.
  processing,

  /// Enough recordings; call [WakeEnroller.finish].
  complete,

  /// Stored.
  saved,

  /// Stopped by the user or an error.
  cancelled,
}

/// Guided enrollment of one speaker (WP60): asks for [target] recordings of
/// „Wendelin“, rejects unusable ones, turns each into an embedding at once
/// and drops the audio. Nothing is stored before [finish].
class WakeEnroller extends ChangeNotifier {
  /// Creates the enroller.
  WakeEnroller({
    required this.audio,
    required this.features,
    required this.store,
    required this.speakerId,
    this.target = 15,
    this.minimum = 8,
    this.threshold = wakeProvisionalThreshold,
    this.pause = const Duration(milliseconds: 900),
    UtteranceCapture Function()? newCapture,
  }) : _newCapture = newCapture ?? UtteranceCapture.new;

  /// Microphone.
  final AudioInput audio;

  /// Feature chain.
  final WakeFeatureExtractor features;

  /// Where [finish] stores the templates.
  final WakeTemplateStore store;

  /// Speaker the templates belong to.
  final String speakerId;

  /// Recordings asked for.
  final int target;

  /// Fewest recordings [finish] accepts.
  final int minimum;

  /// Threshold stored with the templates (until a calibration refines it).
  final double threshold;

  /// Pause after each recording (time to read the result).
  final Duration pause;

  final UtteranceCapture Function() _newCapture;
  final _embeddings = <Float32List>[];
  var _phase = EnrollPhase.idle;
  UtteranceVerdict? _last;
  var _rejected = 0;
  var _level = 0.0;
  Object? _error;
  var _stopped = false;

  /// Current phase.
  EnrollPhase get phase => _phase;

  /// Usable recordings so far.
  int get accepted => _embeddings.length;

  /// Dropped recordings so far.
  int get rejected => _rejected;

  /// Verdict on the latest recording.
  UtteranceVerdict? get lastVerdict => _last;

  /// Level of the latest 20 ms (0–1, square-rooted for display).
  double get level => _level;

  /// Why it stopped (microphone or model failure).
  Object? get error => _error;

  /// Whether [finish] may be called.
  bool get canFinish => accepted >= minimum && _phase != EnrollPhase.saved;

  void _set(EnrollPhase p) {
    _phase = p;
    notifyListeners();
  }

  /// Runs the recordings until [target] is reached or [cancel]. Completes
  /// when stopped; [phase] says how.
  Future<void> run() async {
    if (_phase != EnrollPhase.idle) throw StateError('läuft bereits');
    try {
      await features.open();
      while (!_stopped && accepted < target) {
        _set(EnrollPhase.listening);
        final u = await _record();
        if (_stopped) break;
        if (u == null) {
          throw const MicrophoneEnded();
        }
        await _take(u);
        if (accepted < target) await Future<void>.delayed(pause);
      }
    } on Object catch (e) {
      _error = e;
      _stopped = true;
    }
    await features.close();
    if (_stopped || _error != null) {
      _set(EnrollPhase.cancelled);
    } else {
      _set(EnrollPhase.complete);
    }
  }

  Future<Utterance?> _record() async {
    final capture = _newCapture();
    final done = Completer<Utterance?>();
    late StreamSubscription<Int16List> sub;
    sub = audio.start().listen(
      (frame) {
        final r = capture.feed(frame);
        _level = capture.level;
        if (r != null && !done.isCompleted) done.complete(r);
      },
      onError: (Object e, StackTrace s) {
        if (!done.isCompleted) done.completeError(e, s);
      },
      onDone: () {
        if (!done.isCompleted) done.complete(null);
      },
    );
    try {
      return await done.future;
    } finally {
      await sub.cancel();
      await audio.stop();
      _level = 0;
    }
  }

  Future<void> _take(Utterance u) async {
    _last = u.verdict;
    if (u.verdict != UtteranceVerdict.accepted) {
      _rejected++;
      notifyListeners();
      return;
    }
    _set(EnrollPhase.processing);
    final e = await embedUtterance(features, u.pcm!, u.speechEnd);
    if (e == null) {
      _last = UtteranceVerdict.noSpeech;
      _rejected++;
    } else {
      _embeddings.add(e);
    }
    notifyListeners();
  }

  /// Stops after the current recording; nothing is stored.
  Future<void> cancel() async {
    _stopped = true;
    await audio.stop();
  }

  /// Stores the templates with the provisional threshold (the calibration
  /// refines it), replacing those of the speaker.
  Future<WakeTemplates> finish() async {
    if (!canFinish) throw StateError('zu wenige Aufnahmen');
    final templates = WakeTemplates(
      speakerId: speakerId,
      featureVersion: features.featureVersion,
      threshold: threshold,
      embeddings: List.unmodifiable(_embeddings),
    );
    await store.save(templates);
    _set(EnrollPhase.saved);
    return templates;
  }

  @override
  void dispose() {
    _stopped = true;
    super.dispose();
  }
}
