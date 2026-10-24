import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/lazy_vad.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

final class _Vad implements VoiceActivityDetector {
  int frames = 0;
  int resets = 0;
  @override
  double get threshold => 0.5;
  @override
  double speechProbability(Int16List frame) {
    frames++;
    return 1;
  }

  @override
  void reset() => resets++;
}

void main() {
  late List<_Vad> opened;
  late List<_Vad> closed;
  late LazyVoiceActivityDetector lazy;

  setUp(() {
    opened = [];
    closed = [];
    lazy = LazyVoiceActivityDetector(
      threshold: 0.5,
      open: () => _Vad()..also(opened.add),
      close: (v) => closed.add(v as _Vad),
    );
  });

  test('öffnet erst beim ersten Frame, nicht im Konstruktor', () {
    expect(lazy.isOpen, isFalse);
    expect(opened, isEmpty);
    expect(lazy.speechProbability(Int16List(512)), 1);
    expect(opened, hasLength(1));
    lazy.speechProbability(Int16List(512));
    expect(opened, hasLength(1));
  });

  test('warm öffnet vorab, einmal', () {
    lazy
      ..warm()
      ..warm();
    expect(opened, hasLength(1));
    expect(lazy.isOpen, isTrue);
  });

  test('release schließt; der nächste Frame öffnet neu', () {
    lazy.warm();
    lazy.release();
    expect(closed, [opened.single]);
    expect(lazy.isOpen, isFalse);
    lazy.release();
    expect(closed, hasLength(1), reason: 'doppeltes release schließt nicht');
    lazy.speechProbability(Int16List(512));
    expect(opened, hasLength(2));
  });

  test('Frame nach dispose: 0, kein Öffnen; warm öffnet nicht', () {
    lazy.warm();
    lazy.dispose();
    expect(closed, hasLength(1));
    expect(lazy.speechProbability(Int16List(512)), 0);
    lazy.warm();
    expect(opened, hasLength(1));
    expect(lazy.isOpen, isFalse);
  });

  test('reset geht an den offenen Detektor und öffnet keinen', () {
    lazy.reset();
    expect(opened, isEmpty);
    lazy.warm();
    lazy.reset();
    expect(opened.single.resets, 1);
  });
}

extension<T> on T {
  void also(void Function(T) f) => f(this);
}
