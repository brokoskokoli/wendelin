import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

final class _Named implements WakeVerifier {
  _Named(this.kind, this.verdict);
  @override
  final String kind;
  final bool verdict;
  int calls = 0;

  @override
  Future<bool> confirm(Int16List pcm) async {
    calls++;
    return verdict;
  }
}

void main() {
  group('PreferredWakeVerifier (Parakeet, sonst Whisper)', () {
    late _Named parakeet;
    late _Named whisper;
    PreferredWakeVerifier make(Future<bool> Function() available) =>
        PreferredWakeVerifier(
          preferred: parakeet,
          fallback: whisper,
          available: available,
        );

    setUp(() {
      parakeet = _Named('parakeet', true);
      whisper = _Named('whisper', false);
    });

    test('verfügbar: nur der bevorzugte Prüfer entscheidet', () async {
      final v = make(() async => true);
      expect(await v.confirm(Int16List(10)), isTrue);
      expect(v.kind, 'parakeet');
      expect((parakeet.calls, whisper.calls), (1, 0));
    });

    test('nicht verfügbar: Rückfall, der andere läuft nie', () async {
      final v = make(() async => false);
      expect(await v.confirm(Int16List(10)), isFalse);
      expect(v.kind, 'whisper');
      expect((parakeet.calls, whisper.calls), (0, 1));
    });

    test('Prüfung der Verfügbarkeit wirft: Rückfall', () async {
      final v = make(() async => throw StateError('x'));
      await v.confirm(Int16List(10));
      expect(v.kind, 'whisper');
      expect(whisper.calls, 1);
    });

    test('Entscheidung je Ausschnitt (Modell später installiert)', () async {
      var installed = false;
      final v = make(() async => installed);
      await v.confirm(Int16List(10));
      expect(v.kind, 'whisper');
      installed = true;
      await v.confirm(Int16List(10));
      expect(v.kind, 'parakeet');
    });

    test('Fehler des gewählten Prüfers wird nicht verdeckt', () async {
      final bad = FakeWakeVerifier()..error = StateError('boom');
      final v = PreferredWakeVerifier(
        preferred: bad,
        fallback: whisper,
        available: () async => true,
      );
      await expectLater(v.confirm(Int16List(10)), throwsStateError);
      expect(whisper.calls, 0);
    });
  });
}
