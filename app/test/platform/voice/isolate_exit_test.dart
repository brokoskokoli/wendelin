import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/isolate_exit.dart';

/// Exits when it receives anything (like the Whisper/TTS isolates).
void _polite(SendPort out) {
  final inbox = ReceivePort();
  out.send(inbox.sendPort);
  inbox.listen((_) {
    inbox.close();
    Isolate.exit();
  });
}

/// Ignores the shutdown request and keeps running.
void _stubborn(SendPort out) {
  final inbox = ReceivePort();
  out.send(inbox.sendPort);
  inbox.listen((_) {});
}

Future<(WorkerIsolate, SendPort)> _spawn(void Function(SendPort) entry) async {
  final replies = ReceivePort();
  final worker = await WorkerIsolate.spawn(entry, replies.sendPort);
  final port = await replies.first as SendPort;
  return (worker, port);
}

void main() {
  test('wartet, bis das Isolat selbst endet', () async {
    final (worker, port) = await _spawn(_polite);
    port.send(null);
    expect(await worker.awaitExit(), isTrue);
    expect(worker.killed, isFalse);
  });

  test('beendet ein hängendes Isolat erst nach der Frist', () async {
    final (worker, port) = await _spawn(_stubborn);
    port.send(null);
    final watch = Stopwatch()..start();
    expect(
      await worker.awaitExit(grace: const Duration(milliseconds: 100)),
      isFalse,
    );
    expect(
      watch.elapsed,
      greaterThanOrEqualTo(const Duration(milliseconds: 100)),
    );
  });

  test('kill beim Start-Fehler', () async {
    final (worker, _) = await _spawn(_stubborn);
    worker.kill();
    await worker.exited;
    expect(worker.killed, isTrue);
  });
}
