import 'dart:async';
import 'dart:typed_data';

import '../src/io/speech_to_text.dart';
import '../src/wake/keyword_spec.dart';
import '../src/wake/wake_feature_extractor.dart';
import '../src/wake/wake_templates.dart';
import '../src/wake/wake_verifier.dart';
import '../src/wake/wake_word_engine.dart';

/// [WakeWordEngine] with a script: a hit is reported when a frame starts
/// with the marker sample value [marker] (a frame filled by [markerFrame]),
/// or when [hitAtFrame] says so. Passes `wakeWordEngineContract`.
final class FakeWakeWordEngine implements WakeWordEngine {
  /// Creates the fake. [hitAtFrame]: zero-based frame indexes that produce a
  /// hit (counted since the last [reset]).
  FakeWakeWordEngine({
    this.hitAtFrame = const {},
    this.keywordId = 'wake',
    this.acceptDelay = Duration.zero,
    this.direct = false,
    this.holdMs,
  });

  /// `WakeWordHit.holdMs` of every hit (WP141).
  final int? holdMs;

  /// Hits are sure hits (`WakeWordHit.direct`, WP129).
  final bool direct;

  /// Time [accept] takes per frame (an engine that lags behind the audio).
  final Duration acceptDelay;

  /// The marker sample value.
  static const marker = 12345;

  /// A frame of [samples] samples that makes the fake report a hit.
  static Int16List markerFrame([int samples = 480]) =>
      Int16List(samples)..fillRange(0, samples, marker);

  /// Frames (since reset) that produce a hit.
  final Set<int> hitAtFrame;

  /// Reported keyword id.
  final String keywordId;

  /// Thrown by [accept] when set.
  Object? acceptError;

  bool _open = false;
  int _frames = 0;
  int _samples = 0;

  /// Number of [open] / [reset] / [close] calls.
  int openCount = 0, resetCount = 0, closeCount = 0;

  /// Whether the engine is open.
  bool get isOpen => _open;

  @override
  Future<void> open(List<KeywordSpec> keywords) async {
    if (_open) throw StateError('FakeWakeWordEngine ist bereits offen');
    _open = true;
    openCount++;
  }

  @override
  Future<List<WakeWordHit>> accept(Int16List frame) async {
    if (!_open) throw StateError('FakeWakeWordEngine ist nicht offen');
    if (acceptDelay > Duration.zero) await Future<void>.delayed(acceptDelay);
    final e = acceptError;
    if (e != null) throw e;
    final index = _frames++;
    _samples += frame.length;
    final hit =
        hitAtFrame.contains(index) ||
        (frame.isNotEmpty && frame.first == marker);
    return hit
        ? [
            WakeWordHit(
              keywordId: keywordId,
              endSample: _samples,
              confidence: 0.9,
              direct: direct,
              holdMs: holdMs,
            ),
          ]
        : const [];
  }

  @override
  void reset() {
    _frames = 0;
    _samples = 0;
    resetCount++;
  }

  @override
  Future<void> close() async {
    if (!_open) return;
    _open = false;
    closeCount++;
  }
}

/// [WakeFeatureExtractor] with scripted windows: every [windowEvery]
/// samples one [WakeWindow] built by [windowFor] (default: zero embedding).
final class FakeWakeFeatureExtractor implements WakeSequenceExtractor {
  /// Creates the fake.
  FakeWakeFeatureExtractor({
    this.featureVersion = 'fake-1',
    this.windowEvery = 1280,
    this.windowFor,
    this.embeddingMean,
    this.centerId,
    this.sequenceFor,
  });

  /// Answer of [sequence] for a clip (default: `null`, too short). Every call
  /// is kept in [sequenceCalls].
  Float32List? Function(Int16List clip)? sequenceFor;

  /// The clips [sequence] was asked about.
  final List<Int16List> sequenceCalls = [];

  @override
  Future<Float32List?> sequence(Int16List clip) async {
    sequenceCalls.add(clip);
    return sequenceFor?.call(clip);
  }

  @override
  final String featureVersion;

  @override
  final Float32List? embeddingMean;

  @override
  final String? centerId;

  /// Samples between windows.
  final int windowEvery;

  /// Builds the window for (endSample, frame of the window end).
  WakeWindow Function(int endSample, Int16List frame)? windowFor;

  int _samples = 0;
  bool _open = false;

  /// Whether [open] was called and not closed.
  bool get isOpen => _open;

  @override
  Future<void> open() async => _open = true;

  @override
  Future<List<WakeWindow>> accept(Int16List frame) async {
    final before = _samples ~/ windowEvery;
    _samples += frame.length;
    final n = _samples ~/ windowEvery - before;
    return [
      for (var i = 1; i <= n; i++)
        (windowFor ??
            (end, _) => WakeWindow(endSample: end, embedding: Float32List(4)))(
          (before + i) * windowEvery,
          frame,
        ),
    ];
  }

  @override
  void reset() => _samples = 0;

  @override
  Future<void> close() async => _open = false;
}

/// [WakeVerifier] answering from a script (default: confirms).
final class FakeWakeVerifier implements WakeEnrollVerifier {
  /// Creates the fake; [answer] decides per call (1-based number).
  FakeWakeVerifier({this.answer, this.delay = Duration.zero});

  /// Decides the result for call number n; default `true`.
  bool Function(int n)? answer;

  /// Time one confirmation takes.
  final Duration delay;

  /// While set, [confirm] waits for it (the test decides when the check
  /// ends, frames keep arriving meanwhile).
  Completer<void>? gate;

  /// Thrown by [confirm] when set.
  Object? error;

  /// Audio of every call.
  final List<Int16List> calls = [];

  @override
  String get kind => 'fake';

  @override
  Future<bool> confirm(Int16List pcm) async {
    calls.add(pcm);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    await gate?.future;
    final e = error;
    if (e != null) throw e;
    return answer?.call(calls.length) ?? true;
  }

  /// For the enrollment: what [hear] reports instead of the default
  /// (`heyWendelin` if [confirm] would say yes, else `other`).
  HeardWake? heard;

  @override
  Future<HeardWake> hear(Int16List pcm) async {
    final ok = await confirm(pcm);
    return heard ?? (ok ? HeardWake.heyWendelin : HeardWake.other);
  }
}

/// [SpeechToText] returning a fixed text (for `TranscriptWakeVerifier`).
final class FixedTranscriptStt implements SpeechToText {
  /// Creates the fake.
  FixedTranscriptStt(this.text);

  /// The transcript.
  String text;

  /// Audio length of the last call in samples.
  int lastSamples = 0;

  /// Peak (absolute sample value) of the audio of the last call.
  int lastPeak = 0;

  @override
  SpeechToTextEngineInfo get info =>
      const SpeechToTextEngineInfo(name: 'fixed', languages: {'de'});

  @override
  Future<Transcript> transcribe(Int16List pcm, {String? language}) async {
    lastSamples = pcm.length;
    lastPeak = pcm.fold(0, (p, s) => s.abs() > p ? s.abs() : p);
    return Transcript(text: text);
  }
}

/// In-memory [WakeTemplateStore].
final class FakeWakeTemplateStore implements WakeTemplateStore {
  final _data = <String, WakeTemplates>{};

  @override
  Future<WakeTemplates?> load(String speakerId) async => _data[speakerId];

  @override
  Future<void> save(WakeTemplates templates) async =>
      _data[templates.speakerId] = templates;

  @override
  Future<void> delete(String speakerId) async => _data.remove(speakerId);
}
