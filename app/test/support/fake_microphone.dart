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
  final requests = <bool>[];
  int starts = 0;
  int stops = 0;
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
  Future<Stream<Uint8List>> startStream() async {
    final e = startError;
    if (e != null) throw e;
    starts++;
    // Closed in stop()/endFromPlatform().
    // ignore: close_sinks
    final ctrl = _ctrl = StreamController<Uint8List>();
    var n = 0;
    _timer = Timer.periodic(period, (_) {
      ctrl.add(Uint8List.fromList(List.generate(chunk, (i) => (n + i) & 0xff)));
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

  @override
  Future<void> stop() async {
    stops++;
    _timer?.cancel();
    final c = _ctrl;
    _ctrl = null;
    await c?.close();
  }
}
