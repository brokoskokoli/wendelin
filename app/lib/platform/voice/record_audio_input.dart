import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../voice/voice_log.dart';
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

/// The `RecordConfig` of [profile] (WP72: the interruption mode is `none`).
///
/// The plugin's default `pause` requests audio focus with every recording
/// and pauses the PCM engine on any focus loss, without resuming. The own
/// speech output (system TTS per chunk, `audioplayers`) takes the focus, so
/// the barge-in recording stood still while the answer was spoken.
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
  RecordPcmRecorder([
    AudioRecorder? recorder,
    Future<SpeechCapture> Function()? speechCapture,
  ]) : _given = recorder,
       _speechCapture = speechCapture;

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
    // A pause by the platform would silence the barge-in unnoticed: log it.
    _states ??= _recorder.onStateChanged().listen(
      (s) => voiceLog('mic-state', {'state': s}),
    );
    final stream = await _recorder.startStream(
      buildRecordConfig(profile, speech),
    );
    voiceLog('mic-config', {
      'profile': profile,
      'variant': profile == CaptureProfile.speechOutput ? speech : null,
    });
    return stream;
  }

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }
}

/// Microphone as [AudioInput]: 16 kHz mono 16-bit PCM from [PcmRecorder].
///
/// [start] checks the permission without asking (the app asks first with
/// an explanation, see `ensureMicrophoneAccess`), so a missing permission
/// becomes `VoiceException(permissionDenied)`; any other failure is
/// `VoiceException(unavailable)` on the frame stream.
final class RecordAudioInput implements ProfiledAudioInput {
  /// Creates the input.
  RecordAudioInput([PcmRecorder? recorder])
    : _recorder = recorder ?? RecordPcmRecorder();

  final PcmRecorder _recorder;
  StreamController<Int16List>? _out;
  // Cancelled via a local copy in _finish() and stop().
  // ignore: cancel_subscriptions
  StreamSubscription<Uint8List>? _sub;
  Future<void> _stopping = Future.value();

  CaptureProfile _profile = CaptureProfile.recognition;
  // Chosen while recording; applies at the next start (WP64: the barge-in
  // listener still holds the microphone when the pipeline leaves
  // `speaking`, the follow-up recording must still get `recognition`).
  CaptureProfile? _pending;

  @override
  bool get isRunning => _out != null;

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
    if (_out != null) {
      voiceLog('mic-busy', {'profile': _profile});
      throw const VoiceException(
        VoiceErrorKind.busy,
        'Das Mikrofon war noch belegt. Bitte sprich noch einmal.',
      );
    }
    _profile = _pending ?? _profile;
    _pending = null;
    final out = StreamController<Int16List>();
    _out = out;
    unawaited(_begin(out));
    return out.stream;
  }

  Future<void> _begin(StreamController<Int16List> out) async {
    await _stopping;
    try {
      if (!await _recorder.hasPermission(request: false)) {
        throw const VoiceException(
          VoiceErrorKind.permissionDenied,
          'Wendelin darf das Mikrofon nicht benutzen.',
        );
      }
      final bytes = await _recorder.startStream(_profile);
      voiceLog('mic-start', {'profile': _profile});
      if (!identical(_out, out)) {
        // stop() came first.
        await _recorder.stop();
        return;
      }
      final decoder = PcmBytesDecoder();
      _sub = bytes.listen(
        (chunk) {
          final frame = decoder.convert(chunk);
          if (frame.isNotEmpty && !out.isClosed) out.add(frame);
        },
        onError: (Object e) => _fail(out, e),
        onDone: () => unawaited(_finish(out)),
      );
    } on Object catch (e) {
      _fail(out, e);
    }
  }

  void _fail(StreamController<Int16List> out, Object e) {
    if (!out.isClosed) {
      out.addError(
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
    _stopping = _finish(out, stopRecorder: true);
  }

  Future<void> _finish(
    StreamController<Int16List> out, {
    bool stopRecorder = false,
  }) async {
    if (identical(_out, out)) _out = null;
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    if (stopRecorder) {
      try {
        await _recorder.stop();
      } on Object {
        // Nothing to stop any more.
      }
    }
    if (!out.isClosed) await out.close();
  }

  @override
  Future<void> stop() {
    final out = _out;
    if (out == null) return _stopping;
    _out = null;
    voiceLog('mic-stop');
    return _stopping = () async {
      final sub = _sub;
      _sub = null;
      // Not awaited: a cancelled stream answers with a shared root-zone
      // future; the recorder stop below is what ends the recording.
      unawaited(sub?.cancel());
      try {
        await _recorder.stop();
      } on Object {
        // Already stopped by the platform; the stream ends anyway.
      }
      if (!out.isClosed) unawaited(out.close());
    }();
  }
}
