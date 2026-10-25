import 'dart:async';
import 'dart:typed_data';

import 'package:wendelin/platform/voice/record_audio_input.dart';

/// Recorder stand-in: emits a 20 ms chunk (640 bytes) every [period] until
/// stopped; chunks can be odd-sized to test the byte carry.
final class FakePcmRecorder implements PcmRecorder {
  FakePcmRecorder({
    this.granted = true,
    this.period = const Duration(milliseconds: 5),
    this.chunk = 640,
  });

  bool granted;
  final Duration period;
  final int chunk;
  Object? startError;

  /// [stop] throws this, if set.
  Object? stopError;

  /// Whether the consumer cancelled its subscription to the last stream.
  bool cancelled = false;
  final requests = <bool>[];

  /// Source profile of every started stream.
  final profiles = <CaptureProfile>[];
  int starts = 0;
  int stops = 0;

  /// Chunks emitted so far (all streams).
  int sent = 0;
  // ignore: close_sinks
  StreamController<Uint8List>? _ctrl;
  Timer? _timer;

  bool get running => _ctrl != null;

  @override
  Future<bool> hasPermission({bool request = true}) async {
    requests.add(request);
    return granted;
  }

  @override
  Future<Stream<Uint8List>> startStream([
    CaptureProfile profile = CaptureProfile.recognition,
  ]) async {
    profiles.add(profile);
    final e = startError;
    if (e != null) throw e;
    starts++;
    cancelled = false;
    // Closed in stop()/endFromPlatform().
    // ignore: close_sinks
    final ctrl = _ctrl = StreamController<Uint8List>(
      onCancel: () => cancelled = true,
    );
    var n = 0;
    _timer = Timer.periodic(period, (_) {
      ctrl.add(Uint8List.fromList(List.generate(chunk, (i) => (n + i) & 0xff)));
      sent++;
      n += chunk;
    });
    return ctrl.stream;
  }

  /// Simulates the platform ending the stream (e.g. microphone taken).
  Future<void> endFromPlatform({Object? error}) async {
    _timer?.cancel();
    final c = _ctrl;
    _ctrl = null;
    if (error != null) c?.addError(error);
    await c?.close();
  }

  /// Emits [error] on the stream without ending it (recording goes on).
  void emitError(Object error) => _ctrl!.addError(error);

  @override
  Future<void> stop() async {
    stops++;
    final e = stopError;
    if (e != null) throw e;
    _timer?.cancel();
    final c = _ctrl;
    _ctrl = null;
    // Not awaited, like the plugin's broadcast stream: a stream nobody
    // listened to yet (stop right after start) would never report done.
    unawaited(c?.close());
  }
}
