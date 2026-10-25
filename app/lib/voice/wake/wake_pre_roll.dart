import 'dart:async';
import 'dart:typed_data';

import 'package:wendelin_voice/wendelin_voice.dart';

import '../../di/wake_settings.dart';
import '../../platform/assistant_platform.dart';
import '../voice_log.dart';

/// Takes the audio of the wake word hit from the service and, if [tone] is
/// set, plays the tone (WP68); shared by the overlay and the chat (WP93).
/// The tone follows the take: the service no longer records, the new
/// microphone silences the first [wakeToneMuteSamples] samples. Without a
/// tone (setting) or if the speaker is evidently continuing already,
/// nothing is played and nothing silenced. `null` if nobody left a hit.
Future<WakePreRoll?> takeWakePreRoll({
  required AssistantPlatform platform,
  required bool tone,
  required Future<void> Function() playTone,
}) async {
  // The service records on until the new microphone has its first frame
  // (WP146); `finish` ends that, once.
  final taken = await platform.takeWakeHandoff(keepOpen: true);
  if (taken == null) return null;
  Future<WakeTail?>? finished;
  Future<WakeTail?> finish() => finished ??= platform.finishWakeHandoff().then(
    (t) => t == null ? null : (pcm: t.pcm, lastSampleAtMs: t.lastSampleAtMs),
  );
  final pcm = taken.pcm;
  final continues = speechAfterWakeWord(pcm, taken.wakeEnd);
  voiceLog('wake-handoff', {
    'ms': samplesToDuration(pcm.length),
    'captured': Duration(milliseconds: taken.capturedMs),
    'continues': continues,
  });
  final play = tone && !continues;
  if (play) unawaited(playTone());
  return WakePreRoll(
    pcm: pcm,
    wakeEnd: taken.wakeEnd,
    muteMicSamples: play ? wakeToneMuteSamples : 0,
    lastSampleAtMs: taken.lastSampleAtMs,
    finish: finish,
  );
}

/// How long [WakeHandoffTracker.close] waits for the first frame of the app's
/// microphone before it ends the service anyway (below the service's guard).
const wakeFirstFrameWait = Duration(milliseconds: 2000);

/// The longest hole that is filled with silence; a larger one is not a
/// handover hole (WP146).
const wakeHoleMax = Duration(milliseconds: 1500);

/// Joins [pre] and what the service recorded afterwards ([tail]) to the first
/// frame of the new microphone (WP146):
///
/// - the tail starts at the take, where the confirmation tone starts too: its
///   first [WakePreRoll.muteMicSamples] samples are silenced (the service
///   would record the tone), and the new microphone mutes only the rest;
/// - the service recorded on until after that first frame: the doubled end of
///   the tail is cut (negative gap), no word comes twice;
/// - a hole that remains (positive gap) is inserted as silence (at most
///   [wakeHoleMax]), so words are not glued together.
///
/// Logs `wake-gap` (signed gap in ms, `tail`, `trim`, `silence`; numbers only).
WakePreRoll bridgeWakeTail(
  WakePreRoll pre,
  WakeTail tail, {
  int? firstFrameAtMs,
  int? firstFrameSamples,
  int? afterTakeMs,
}) {
  var audio = Int16List.fromList(tail.pcm);
  final muted = pre.muteMicSamples < audio.length
      ? pre.muteMicSamples
      : audio.length;
  audio.fillRange(0, muted, 0);
  final last = tail.lastSampleAtMs;
  int? gap;
  if (last != null && last > 0 && firstFrameAtMs != null) {
    gap = wakeGapMs(
      firstFrameAtMs: firstFrameAtMs,
      frameSamples: firstFrameSamples ?? 0,
      lastSampleAtMs: last,
    );
  }
  var trim = 0;
  var silence = 0;
  if (gap != null && gap < 0) {
    trim = (-gap * 16).clamp(0, audio.length).toInt();
    audio = Int16List.sublistView(audio, 0, audio.length - trim);
  } else if (gap != null && gap > 0) {
    silence = durationToSamples(Duration(milliseconds: gap));
    final max = durationToSamples(wakeHoleMax);
    if (silence > max) silence = max;
  }
  final out = Int16List(pre.pcm.length + audio.length + silence)
    ..setAll(0, pre.pcm)
    ..setAll(pre.pcm.length, audio);
  final added = audio.length + silence;
  voiceLog('wake-gap', {
    'ms': ?gap,
    'afterTake': ?afterTakeMs,
    'mode': 'overlap',
    'tail': samplesToDuration(tail.pcm.length),
    'trim': samplesToDuration(trim),
    'silence': samplesToDuration(silence),
  });
  return pre.withAudio(
    out,
    muteMicSamples: pre.muteMicSamples > added ? pre.muteMicSamples - added : 0,
    // After a measured gap the audio is continuous up to the first frame;
    // without a first frame the first one is measured against the tail.
    lastSampleAtMs: gap != null ? null : last,
  );
}

/// What the service recorded between taking the hit and the first frame of the
/// app's microphone (WP146), and when its last sample arrived.
typedef WakeTail = ({Int16List pcm, int? lastSampleAtMs});

/// What a wake word hit leaves for the recording (WP68): the audio from the
/// end of the wake word on, gap-free up to the service's last sample
/// ([lastSampleAtMs]), and how much of the first samples of the new
/// microphone to silence (confirmation tone).
final class WakePreRoll {
  /// Creates the pre-roll.
  const WakePreRoll({
    required this.pcm,
    this.wakeEnd,
    this.muteMicSamples = 0,
    this.lastSampleAtMs,
    this.finish,
  });

  /// 16 kHz mono PCM.
  final Int16List pcm;

  /// Sample in [pcm] where the wake word ends.
  final int? wakeEnd;

  /// Samples of the new microphone to zero (tone).
  final int muteMicSamples;

  /// Wall clock (ms since epoch) of the last sample the service recorded; the
  /// difference to the first sample of the new microphone is the hole.
  final int? lastSampleAtMs;

  /// WP146: the service still records (taken with `keepOpen`); calling this
  /// stops it and returns what it recorded since, once. `null`: nothing is
  /// kept open.
  final Future<WakeTail?> Function()? finish;

  /// Copy with other audio, tone mute and [lastSampleAtMs] (the bridged
  /// pre-roll; `null` = the audio reaches the microphone without a hole).
  WakePreRoll withAudio(
    Int16List pcm, {
    required int muteMicSamples,
    int? lastSampleAtMs,
  }) => WakePreRoll(
    pcm: pcm,
    wakeEnd: wakeEnd,
    muteMicSamples: muteMicSamples,
    lastSampleAtMs: lastSampleAtMs,
  );
}

/// The hole in ms between the service's last sample (arrival of its last
/// chunk) and the first sample of the new microphone: its first frame
/// arrives [frameSamples] after the frame began (WP68).
int wakeGapMs({
  required int firstFrameAtMs,
  required int frameSamples,
  required int lastSampleAtMs,
}) => firstFrameAtMs - frameSamples * 1000 ~/ 16000 - lastSampleAtMs;

/// The state of one wake word hit between taking it and the first frame of
/// the app's microphone (WP68, WP73, WP146): the hit with the still recording
/// service, the answer of its `finish`, and the first frame for `wake-gap`.
final class WakeHandoffTracker {
  /// Wall clock of the service's last sample, as long as no first frame
  /// has been measured against it.
  int? lastSampleAt;

  /// The hit whose service microphone still records (taken with `keepOpen`).
  WakePreRoll? handoff;

  Future<WakeTail?>? _tail;
  Completer<void>? _frame;

  /// The hit's service microphone still records. Without it no `await`
  /// separates the state change from the pipeline start (as before WP146).
  bool kept(WakePreRoll? pre) => pre?.finish != null;
  Stopwatch? _take;
  int? _firstFrameAtMs;
  int? _firstFrameSamples;
  int? _afterTakeMs;

  /// A new start: forgets the previous hit.
  void reset() {
    _firstFrameAtMs = null;
    handoff = null;
    _tail = null;
    _frame = null;
  }

  /// The hit is taken, before the microphone opens: its first frame is
  /// measured against [pre]. Splits the hole (WP73): service close /
  /// hand-over (`ms` minus `afterTake`) and the opening of this microphone
  /// (`afterTake`).
  void begin(WakePreRoll? pre) {
    lastSampleAt = pre?.lastSampleAtMs;
    handoff = pre?.finish == null ? null : pre;
    _frame = handoff == null ? null : Completer<void>();
    _take = pre == null ? null : (Stopwatch()..start());
  }

  /// The first frame of the app's microphone: the service stops now and
  /// `wake-gap` is logged (numbers only; with a kept-open service when the
  /// tail is bridged, see [close]).
  void onFirstFrame(int samples) {
    _firstFrameAtMs = DateTime.now().millisecondsSinceEpoch;
    _firstFrameSamples = samples;
    _afterTakeMs = _take?.elapsedMilliseconds;
    final seen = _frame;
    if (seen != null && !seen.isCompleted) seen.complete();
    final kept = handoff?.finish;
    if (kept != null) {
      _tail ??= kept();
      lastSampleAt = null;
    }
    final last = lastSampleAt;
    if (last != null && last > 0) {
      // Hole between the service's last sample and the first sample of this
      // microphone (WP68), without content.
      voiceLog('wake-gap', {
        'ms': wakeGapMs(
          firstFrameAtMs: _firstFrameAtMs!,
          frameSamples: samples,
          lastSampleAtMs: last,
        ),
        'afterTake': ?_afterTakeMs,
      });
    }
    lastSampleAt = null;
    _take = null;
  }

  /// The early microphone is not used (other input): no first frame to wait
  /// for.
  void noFrameExpected() {
    final seen = _frame;
    if (seen != null && !seen.isCompleted) seen.complete();
  }

  /// Ends the service's recording of a hit taken with `keepOpen` and returns
  /// the pre-roll with what it recorded meanwhile, joined to the first frame
  /// of this microphone without a hole or doubled audio (WP146). With the
  /// early microphone ([wait]) it waits for its first frame (at most
  /// [wakeFirstFrameWait]): when the models are warm it would otherwise stop
  /// the service before the app records and the hole stays.
  Future<WakePreRoll?> close(WakePreRoll? pre, {bool wait = true}) async {
    final finish = pre?.finish;
    if (pre == null || finish == null) return pre;
    final seen = _frame;
    if (wait && seen != null && !seen.isCompleted) {
      await seen.future.timeout(wakeFirstFrameWait, onTimeout: () {});
    }
    final tail = await (_tail ??= finish());
    handoff = null;
    _tail = null;
    if (tail == null) return pre;
    return bridgeWakeTail(
      pre,
      tail,
      firstFrameAtMs: _firstFrameAtMs,
      firstFrameSamples: _firstFrameSamples,
      afterTakeMs: _afterTakeMs,
    );
  }
}
