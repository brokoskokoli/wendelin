import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../voice/voice_log.dart';
import '../channel_audio_focus_port.dart';
import 'pcm.dart';

/// Which source the microphone records from.
enum CaptureProfile {
  /// Speech recognition (default): `VOICE_RECOGNITION`, no automatic gain
  /// on most devices. The only profile of every request to Whisper.
  recognition,

  /// During the speech output (barge-in, K23 c): `VOICE_COMMUNICATION`
  /// with the acoustic echo canceler, so the own voice is suppressed.
  speechOutput,
}

/// Which capture the profile [CaptureProfile.speechOutput] uses (WP72).
///
/// The default is the concept's choice (K23 c). The other two are device
/// experiments, chosen by the hidden developer setting „Barge-in-Variante“
/// (`debug.bargeSource`): which one lets „Stopp“/„Wendelin“ through on the
/// Xiaomi can only be decided on the device.
enum SpeechCapture {
  /// `VOICE_COMMUNICATION` with the plugin's `AcousticEchoCanceler`.
  communication,

  /// `VOICE_RECOGNITION` (the source of the enrollment) with the echo
  /// canceler.
  recognitionAec,

  /// `VOICE_RECOGNITION` without any effect (reference: the own voice is not
  /// suppressed, but the speaker may trigger).
  recognition;

  /// The variant with [name], else the default.
  static SpeechCapture parse(String? name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => SpeechCapture.communication,
  );
}

/// The `RecordConfig` of [profile] (WP72).
///
/// The plugin's focus handling is off (`none`) for every profile: it asks for
/// `AUDIOFOCUS_GAIN`, which pauses a running media player for good (WP90).
/// Instead [RecordPcmRecorder] holds the own transient focus (`listen`) while
/// a command is recorded; during the speech output the `duck` focus of the
/// answer is already held and the barge-in recording takes none.
RecordConfig buildRecordConfig(
  CaptureProfile profile, [
  SpeechCapture speech = SpeechCapture.communication,
]) {
  final out = profile == CaptureProfile.speechOutput;
  final aec = out && speech != SpeechCapture.recognition;
  final communication = out && speech == SpeechCapture.communication;
  return RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: AudioInput.sampleRate,
    numChannels: 1,
    echoCancel: aec,
    audioInterruption: AudioInterruptionMode.none,
    androidConfig: AndroidRecordConfig(
      audioSource: communication
          ? AndroidAudioSource.voiceCommunication
          : AndroidAudioSource.voiceRecognition,
    ),
  );
}

/// A microphone whose source can be chosen before it starts.
abstract interface class ProfiledAudioInput implements AudioInput {
  /// Source of the next [start] (a running recording keeps its source).
  CaptureProfile get profile;

  /// Chooses the source of the next [start]. While [isRunning] the running
  /// recording keeps its source and the choice waits for the next start
  /// (returns `false`); otherwise it is applied at once (returns `true`).
  bool useProfile(CaptureProfile profile);
}

/// The part of the `record` plugin that [RecordAudioInput] uses
/// (replaceable in tests).
abstract interface class PcmRecorder {
  /// Whether the microphone permission is granted; with [request] Android
  /// asks the user.
  Future<bool> hasPermission({bool request = true});

  /// Starts a 16 kHz mono PCM stream (little-endian bytes) from the source
  /// of [profile].
  Future<Stream<Uint8List>> startStream([
    CaptureProfile profile = CaptureProfile.recognition,
  ]);

  /// Stops the stream.
  Future<void> stop();
}

/// [PcmRecorder] on `package:record` (Android `AudioRecord`, no GMS).
final class RecordPcmRecorder implements PcmRecorder {
  /// Creates the recorder; [recorder] is created lazily. [speechCapture]
  /// returns the variant for [CaptureProfile.speechOutput] (WP72, developer
  /// setting; default [SpeechCapture.communication]).
  ///
  /// [focus] receives the transient `listen` focus while a command (not the
  /// barge-in during the answer) is recorded.
  RecordPcmRecorder([
    AudioRecorder? recorder,
    Future<SpeechCapture> Function()? speechCapture,
    AudioFocusPort? focus,
  ]) : _given = recorder,
       _speechCapture = speechCapture,
       _focus = focus;

  final AudioFocusPort? _focus;
  bool _listening = false;
  bool _paused = false;
  // Cancelled in _endListening().
  // ignore: cancel_subscriptions
  StreamSubscription<AudioFocusChange>? _focusSub;
  final AudioRecorder? _given;
  final Future<SpeechCapture> Function()? _speechCapture;
  late final AudioRecorder _recorder = _given ?? AudioRecorder();
  // Lives as long as the recorder.
  // ignore: cancel_subscriptions
  StreamSubscription<RecordState>? _states;

  @override
  Future<bool> hasPermission({bool request = true}) =>
      _recorder.hasPermission(request: request);

  @override
  Future<Stream<Uint8List>> startStream([
    CaptureProfile profile = CaptureProfile.recognition,
  ]) async {
    var speech = SpeechCapture.communication;
    if (profile == CaptureProfile.speechOutput) {
      try {
        speech = await (_speechCapture?.call() ?? Future.value(speech));
      } on Object {
        // Settings unreadable: the default.
      }
    }
    if (profile != CaptureProfile.speechOutput && _focus != null) {
      _listening = true;
      _focusSub = _focus.changes.listen(_onFocus);
      await _focus.acquire(AudioFocusKind.listen);
    }
    // A pause by the platform would silence the barge-in unnoticed: log it.
    _states ??= _recorder.onStateChanged().listen(
      (s) => voiceLog('mic-state', {'state': s}),
    );
    final Stream<Uint8List> stream;
    try {
      stream = await _recorder.startStream(buildRecordConfig(profile, speech));
    } on Object {
      await _endListening();
      rethrow;
    }
    voiceLog('mic-state', {'state': 'started'});
    voiceLog('mic-config', {
      'profile': profile,
      'variant': profile == CaptureProfile.speechOutput ? speech : null,
    });
    return stream;
  }

  @override
  Future<void> stop() async {
    try {
      await _recorder.stop();
    } finally {
      await _endListening();
    }
  }

  Future<void> _endListening() async {
    if (!_listening) return;
    _listening = false;
    _paused = false;
    final sub = _focusSub;
    _focusSub = null;
    await sub?.cancel();
    await _focus?.release(AudioFocusKind.listen);
  }

  // Another app (a call, an alarm) took the focus: the recording pauses
  // instead of capturing it, and continues when the focus is back.
  void _onFocus(AudioFocusChange change) {
    if (change.kind != AudioFocusKind.listen || !_listening) return;
    if (change.lost == _paused) return;
    _paused = change.lost;
    voiceLog('mic-focus', {'lost': change.lost});
    unawaited(() async {
      try {
        if (change.lost) {
          await _recorder.pause();
        } else {
          await _recorder.resume();
        }
      } on Object {
        // Not recording any more.
      }
    }());
  }
}

/// One recording of [RecordAudioInput]: its recorder, frame stream and
/// subscription.
final class _Take {
  _Take(this.recorder, this.out);

  final PcmRecorder recorder;
  final StreamController<Int16List> out;
  // Cancelled via a local copy in _finish(), stop() and the end of a
  // detached recording.
  // ignore: cancel_subscriptions
  StreamSubscription<Uint8List>? sub;
}

/// Microphone as [AudioInput]: 16 kHz mono 16-bit PCM from [PcmRecorder].
///
/// [start] checks the permission without asking (the app asks first with
/// an explanation, see `ensureMicrophoneAccess`), so a missing permission
/// becomes `VoiceException(permissionDenied)`; any other failure is
/// `VoiceException(unavailable)` on the frame stream.
///
/// With a second recorder ([spare]) the running recording can be detached
/// (WP146, [DetachableAudioInput]): it goes on in the background and the next
/// [start] uses the other recorder. At most one is detached at a time.
final class RecordAudioInput
    implements ProfiledAudioInput, DetachableAudioInput {
  /// Creates the input.
  ///
  /// [beforeStart] runs before every recording opens the microphone (WP146:
  /// the spoken answer gives the call path back first, see
  /// `SpeechFocus.settle`); [audioMode] reads `AudioManager.mode` for the
  /// `mic-start` log line; [spare] makes the second recorder for [detach].
  RecordAudioInput([
    PcmRecorder? recorder,
    Future<void> Function()? beforeStart,
    Future<int?> Function()? audioMode,
    PcmRecorder Function()? spare,
  ]) : _recorder = recorder ?? RecordPcmRecorder(),
       _beforeStart = beforeStart,
       _audioMode = audioMode,
       _makeSpare = spare;

  PcmRecorder _recorder;
  PcmRecorder? _spare;
  final PcmRecorder Function()? _makeSpare;
  final Future<void> Function()? _beforeStart;
  final Future<int?> Function()? _audioMode;
  _Take? _take;
  _Take? _detached;
  Future<void> _stopping = Future.value();

  CaptureProfile _profile = CaptureProfile.recognition;
  // Chosen while recording; applies at the next start (WP64: the barge-in
  // listener still holds the microphone when the pipeline leaves
  // `speaking`, the follow-up recording must still get `recognition`).
  CaptureProfile? _pending;

  @override
  bool get isRunning => _take != null;

  @override
  CaptureProfile get profile => _profile;

  @override
  bool useProfile(CaptureProfile profile) {
    if (isRunning) {
      _pending = profile == _profile ? null : profile;
      return false;
    }
    _profile = profile;
    _pending = null;
    return true;
  }

  @override
  Stream<Int16List> start() {
    if (_take != null) {
      voiceLog('mic-busy', {'profile': _profile});
      throw const VoiceException(
        VoiceErrorKind.busy,
        'Das Mikrofon war noch belegt. Bitte sprich noch einmal.',
      );
    }
    _profile = _pending ?? _profile;
    _pending = null;
    final take = _Take(_recorder, StreamController<Int16List>());
    _take = take;
    unawaited(_begin(take));
    return take.out.stream;
  }

  @override
  Future<void> Function()? detach() {
    final take = _take;
    if (take == null || take.sub == null || _detached != null) return null;
    final spare = _spare ??= _makeSpare?.call();
    if (spare == null) return null;
    _detached = take;
    _take = null;
    _spare = take.recorder;
    _recorder = spare;
    // What is recorded next is a command, never the speech output.
    _profile = CaptureProfile.recognition;
    _pending = null;
    voiceLog('mic-detach');
    return () => _endDetached(take);
  }

  Future<void> _endDetached(_Take take) async {
    if (!identical(_detached, take)) return;
    _detached = null;
    final sub = take.sub;
    take.sub = null;
    unawaited(sub?.cancel());
    try {
      await take.recorder.stop();
    } on Object {
      // Already stopped by the platform.
    }
    if (!take.out.isClosed) unawaited(take.out.close());
    voiceLog('mic-detach-end');
  }

  Future<void> _begin(_Take take) async {
    await _stopping;
    try {
      // The follow-up recording must not start in the call path of the
      // answer (WP146).
      await _beforeStart?.call();
      if (!await take.recorder.hasPermission(request: false)) {
        throw const VoiceException(
          VoiceErrorKind.permissionDenied,
          'Wendelin darf das Mikrofon nicht benutzen.',
        );
      }
      // Asked before the start, awaited after it: a channel that never
      // answers (tests, no plugin) must not keep stop() from ending this take.
      final mode = _audioMode?.call();
      // WP149 (numbers only, so it reaches the log in every build): wall clock of the open call, of
      // the stream being up and of the first chunk, to explain the time
      // between opening the microphone and its first frame.
      final openAt = DateTime.now().millisecondsSinceEpoch;
      final bytes = await take.recorder.startStream(_profile);
      final startedAt = DateTime.now().millisecondsSinceEpoch;
      final profile = _profile;
      if (!identical(_take, take)) {
        // stop() came first.
        await take.recorder.stop();
        return;
      }
      final decoder = PcmBytesDecoder();
      var firstChunk = false;
      take.sub = bytes.listen(
        (chunk) {
          if (!firstChunk) {
            firstChunk = true;
            final now = DateTime.now().millisecondsSinceEpoch;
            voiceLog('mic-open-timing', {
              'openAt': openAt,
              'startMs': startedAt - openAt,
              'firstChunkMs': now - startedAt,
              'bytes': chunk.length,
            });
          }
          final frame = decoder.convert(chunk);
          if (frame.isNotEmpty && !take.out.isClosed) take.out.add(frame);
        },
        onError: (Object e) => _fail(take, e),
        onDone: () => _stopping = _finish(take),
      );
      Object? audioMode;
      try {
        audioMode = await mode;
      } on Object {
        // The log line must not end a running recording.
      }
      voiceLog('mic-start', {'profile': profile, 'mode': audioMode});
    } on Object catch (e) {
      _fail(take, e);
    }
  }

  void _fail(_Take take, Object e) {
    if (!take.out.isClosed) {
      take.out.addError(
        e is VoiceException
            ? e
            : VoiceException(
                VoiceErrorKind.unavailable,
                e is PlatformException
                    ? 'Das Mikrofon ist nicht verfügbar.'
                    : 'Die Aufnahme ist fehlgeschlagen.',
                cause: e,
              ),
      );
    }
    // The platform may still be recording (an error does not always end
    // the stream): stop it, and let a new start wait for that.
    _stopping = _finish(take, stopRecorder: true);
  }

  Future<void> _finish(_Take take, {bool stopRecorder = false}) async {
    // The stream ended by itself (nobody called stop()): the recorder and its
    // focus still have to be given back.
    final ended = identical(_take, take) || identical(_detached, take);
    if (identical(_take, take)) _take = null;
    if (identical(_detached, take)) _detached = null;
    final sub = take.sub;
    take.sub = null;
    await sub?.cancel();
    if (stopRecorder || ended) {
      try {
        await take.recorder.stop();
      } on Object {
        // Nothing to stop any more.
      }
    }
    if (!take.out.isClosed) await take.out.close();
  }

  @override
  Future<void> stop() {
    final take = _take;
    if (take == null) return _stopping;
    _take = null;
    voiceLog('mic-stop');
    return _stopping = () async {
      final sub = take.sub;
      take.sub = null;
      // Not awaited: a cancelled stream answers with a shared root-zone
      // future; the recorder stop below is what ends the recording.
      unawaited(sub?.cancel());
      try {
        await take.recorder.stop();
      } on Object {
        // Already stopped by the platform; the stream ends anyway.
      }
      if (!take.out.isClosed) unawaited(take.out.close());
    }();
  }
}
