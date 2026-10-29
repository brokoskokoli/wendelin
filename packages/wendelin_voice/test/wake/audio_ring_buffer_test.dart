import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

Int16List ramp(int from, int n) =>
    Int16List.fromList([for (var i = 0; i < n; i++) from + i]);

void main() {
  group('AudioRingBuffer', () {
    test('Standardkapazität ist mindestens 5–6 Sekunden', () {
      final b = AudioRingBuffer();
      expect(b.capacity.inSeconds, inInclusiveRange(5, 6));
      expect(b.capacityInSamples, inInclusiveRange(5 * 16000, 6 * 16000));
    });

    test('Kapazität von 6 Sekunden wird unterstützt (kein Fehler wie bei altem PreRollBuffer)', () {
      final b = AudioRingBuffer(capacity: const Duration(seconds: 6));
      expect(b.capacity, const Duration(seconds: 6));
      expect(b.capacityInSamples, 96000);
    });

    test('Ungültige Kapazität (<= 0 oder über Obergrenze) wird abgelehnt', () {
      expect(
        () => AudioRingBuffer(capacity: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => AudioRingBuffer(capacity: const Duration(seconds: -1)),
        throwsArgumentError,
      );
      expect(
        () => AudioRingBuffer(capacity: const Duration(minutes: 5)),
        throwsArgumentError,
      );
    });

    test('Rollender Puffer hält genau die letzten N Samples', () {
      final b = AudioRingBuffer(
        capacity: const Duration(milliseconds: 100),
      ); // 1600 Samples
      for (var i = 0; i < 10; i++) {
        b.add(ramp(i * 320, 320));
      }
      expect(b.length, 1600);
      final s = b.snapshot();
      expect(s.length, 1600);
      expect(s.first, 3200 - 1600);
      expect(s.last, 3200 - 1);
    });

    test('Entnahme beliebiger Zeitbereiche: snapshot, range, slice', () {
      final b = AudioRingBuffer(capacity: const Duration(seconds: 5));
      b.add(ramp(0, 8000)); // 500 ms

      // Snapshot komplett und mit last
      expect(b.snapshot().length, 8000);
      expect(
        b.snapshot(last: const Duration(milliseconds: 100)),
        ramp(6400, 1600),
      );

      // Range nach Sample-Indizes
      expect(b.range(1000, 2000), ramp(1000, 1000));
      expect(b.range(7000, 8000), ramp(7000, 1000));

      // Slice nach Duration
      final sl = b.slice(
        from: const Duration(milliseconds: 100),
        duration: const Duration(milliseconds: 200),
      );
      expect(sl, ramp(1600, 3200));

      // Slice mit ungültigen/geklemmten Bereichen
      expect(b.range(-10, 500).length, 500);
      expect(b.range(7500, 9000).length, 500);
    });

    test(
      'Hold-Modus: Puffer wächst während Verifikation und verwirft keine Daten',
      () {
        final b = AudioRingBuffer(
          capacity: const Duration(milliseconds: 100),
        ); // 1600 Samples
        b.add(ramp(0, 1600)); // Puffer voll

        b.hold();
        expect(b.isHeld, isTrue);

        // Weitere Daten während der Prüfung einspeisen (über die Kapazität hinaus)
        b.add(ramp(1600, 3200)); // Noch 200 ms dazu
        expect(b.length, 4800); // 1600 + 3200 = 4800 Samples gehalten!
        final s = b.snapshot();
        expect(s.length, 4800);
        expect(s.first, 0); // Älteste Daten wurden NICHT verworfen!
        expect(s.last, 4799);
      },
    );

    test('Verwurf (Discard): Überzählige Daten fallen weg, Puffer rollt wieder auf Kapazität', () {
      final b = AudioRingBuffer(
        capacity: const Duration(milliseconds: 100),
      ); // 1600 Samples
      b.add(ramp(0, 1600));
      b.hold();
      b.add(ramp(1600, 3200)); // Auf 4800 gewachsen
      expect(b.length, 4800);

      // Kandidat verworfen: ältere Daten weg, nur noch die letzten 1600 Samples
      b.release(discard: true);
      expect(b.isHeld, isFalse);
      expect(b.length, 1600);
      final s = b.snapshot();
      expect(s.length, 1600);
      expect(s.first, 4800 - 1600);
      expect(s.last, 4799);

      // Rollen geht normal weiter
      b.add(ramp(4800, 320));
      expect(b.length, 1600);
      expect(b.snapshot().last, 5119);
    });

    test('Bestätigung (Confirm): Alle gesammelten Daten bleiben erhalten', () {
      final b = AudioRingBuffer(
        capacity: const Duration(milliseconds: 100),
      ); // 1600 Samples
      b.add(ramp(0, 1600));
      b.hold();
      b.add(ramp(1600, 3200));
      b.release(discard: false);

      expect(b.isHeld, isFalse);
      expect(b.length, 4800);
      expect(b.snapshot().first, 0);
      expect(b.snapshot().last, 4799);
    });

    test('clear leert den Puffer und setzt Zustand zurück', () {
      final b = AudioRingBuffer()..add(ramp(0, 1000));
      b.hold();
      b.clear();
      expect(b.length, 0);
      expect(b.isHeld, isFalse);
      expect(b.snapshot(), isEmpty);
    });
  });
}
