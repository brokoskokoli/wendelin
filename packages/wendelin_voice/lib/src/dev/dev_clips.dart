import 'dart:typed_data';

import '../io/audio_input.dart';
import '../wake/pre_roll_buffer.dart';

/// Audio on each side of a candidate in its clip (WP148).
const devClipSpan = Duration(seconds: 2);

/// A piece of audio that the developer mode keeps (WP148): 16 kHz mono PCM16.
final class DevClip {
  /// Creates a clip.
  const DevClip({
    required this.event,
    required this.pcm,
    required this.at,
    this.marksMs = const {},
  });

  /// What the clip is (`wake-cand`, `wake-verify`, `barge-cand`,
  /// `barge-verify`, `rec`); part of the file name.
  final String event;

  /// The samples.
  final Int16List pcm;

  /// The moment of the event (not of the writing).
  final DateTime at;

  /// Where things lie in [pcm], in ms from its start (`cand`, `wakeEnd`,
  /// `speechStart` …); the log line carries them next to the file name.
  final Map<String, int> marksMs;
}

/// The way the voice code hands audio to the developer mode (WP148).
///
/// [enabled] is asked before any audio is collected, so nothing is buffered
/// or written without the developer mode. A failing [write] never touches the
/// voice path.
final class DevClips {
  /// Creates the hook.
  const DevClips({required this.enabled, required this.write});

  /// Whether the developer mode is on right now.
  final bool Function() enabled;

  /// Takes a finished clip (must not block: the app writes asynchronously).
  final void Function(DevClip clip) write;

  /// [enabled], a throwing check counts as off (fail closed).
  bool get on {
    try {
      return enabled();
    } on Object {
      return false;
    }
  }

  /// Hands a clip of [pcm] (time stamp now) over, with the place [mark]
  /// ([markSamples] into the clip).
  void emitMarked(String event, Int16List pcm, String mark, int markSamples) =>
      emit(
        DevClip(
          event: event,
          pcm: pcm,
          at: DateTime.now(),
          marksMs: {mark: samplesToDuration(markSamples).inMilliseconds},
        ),
      );

  /// Hands [clip] over if the mode is on.
  void emit(DevClip clip) {
    if (!on) return;
    try {
      write(clip);
    } on Object {
      // Never into the voice path.
    }
  }
}

/// A clip around a moment: [before] is what lay before it, then [after]
/// samples are collected from the frames that follow ([DevClips] need the
/// audio after the candidate too). Marks `cand` (the moment in the file) and
/// `post` (how much really came after it; below [afterWanted] the clip was
/// cut short by a stop or a pause).
final class DevAround {
  /// Creates the collector; [already] is audio after the moment that exists.
  DevAround({
    required this.event,
    required this.before,
    required this.afterWanted,
    Int16List? already,
    DateTime? at,
  }) : at = at ?? DateTime.now() {
    if (already != null && already.isNotEmpty) _add(already);
  }

  /// Event name.
  final String event;

  /// Event time.
  final DateTime at;

  /// Audio up to the moment.
  final Int16List before;

  /// Samples wanted after the moment.
  final int afterWanted;

  final _after = <Int16List>[];
  int _afterLen = 0;

  /// Whether enough audio came after the moment.
  bool get complete => _afterLen >= afterWanted;

  /// Adds the next [frame]; `true` once [complete].
  bool add(Int16List frame) {
    if (!complete) _add(frame);
    return complete;
  }

  void _add(Int16List frame) {
    _after.add(frame);
    _afterLen += frame.length;
  }

  /// The clip with what is there (also when cut short).
  DevClip build() {
    final post = _afterLen < afterWanted ? _afterLen : afterWanted;
    final out = Int16List(before.length + post)..setAll(0, before);
    var at0 = before.length;
    for (final f in _after) {
      if (at0 >= out.length) break;
      final n = out.length - at0 < f.length ? out.length - at0 : f.length;
      out.setRange(at0, at0 + n, f);
      at0 += n;
    }
    return DevClip(
      event: event,
      pcm: out,
      at: at,
      marksMs: {
        'cand': samplesToDuration(before.length).inMilliseconds,
        'post': samplesToDuration(post).inMilliseconds,
      },
    );
  }
}

/// Open [DevAround] collectors of one detector.
final class DevAroundSet {
  /// Creates the set.
  DevAroundSet(this.clips);

  /// The hook; `null` = nothing is collected.
  final DevClips? clips;

  final _open = <DevAround>[];

  /// Most collectors open at once (a candidate storm must not pile up audio).
  static const maxOpen = 4;

  /// Whether collecting is on.
  bool get on => clips?.on ?? false;

  /// Starts a collector if the mode is on.
  void start(DevAround Function() make) {
    if (!on || _open.length >= maxOpen) return;
    _open.add(make());
  }

  /// Starts the `event` collector with the last [devClipSpan] of [ring]
  /// before the moment (taken only if the mode is on) and [devClipSpan]
  /// after it.
  void startLast(String event, PreRollBuffer ring) => start(
    () => DevAround(
      event: event,
      before: ring.snapshot(last: devClipSpan),
      afterWanted: durationToSamples(devClipSpan),
    ),
  );

  /// [DevClips.emitMarked] if the hook is set.
  void emitMarked(String event, Int16List pcm, String mark, int samples) =>
      clips?.emitMarked(event, pcm, mark, samples);

  /// Gives [frame] to the open collectors; finished ones are emitted.
  void feed(Int16List frame) {
    if (_open.isEmpty) return;
    _open.removeWhere((a) {
      if (!a.add(frame)) return false;
      clips?.emit(a.build());
      return true;
    });
  }

  /// Emits what is there (stop, pause, end of the stream).
  void flush() {
    for (final a in _open) {
      clips?.emit(a.build());
    }
    _open.clear();
  }

  /// Forgets all without emitting.
  void clear() => _open.clear();
}
