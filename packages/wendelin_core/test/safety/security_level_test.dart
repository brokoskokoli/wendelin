import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';

void main() {
  // Eine Zeile je Fall: Stufe × gesperrt × Stimme → Ergebnis.
  const a = LevelAccess.allowed;
  const c = LevelAccess.confirm;
  const u = LevelAccess.unlock;
  final table = <(SecurityLevel?, bool, bool, LevelAccess)>[
    (SecurityLevel.a, false, false, a),
    (SecurityLevel.a, false, true, a),
    (SecurityLevel.a, true, false, a),
    (SecurityLevel.a, true, true, a),
    (SecurityLevel.b, false, false, a),
    (SecurityLevel.b, false, true, a),
    (SecurityLevel.b, true, false, u),
    (SecurityLevel.b, true, true, a),
    (SecurityLevel.c, false, false, a),
    (SecurityLevel.c, false, true, a),
    (SecurityLevel.c, true, false, u),
    (SecurityLevel.c, true, true, u),
    (SecurityLevel.d, false, false, c),
    (SecurityLevel.d, false, true, c),
    (SecurityLevel.d, true, false, u),
    (SecurityLevel.d, true, true, u),
    // Fail-closed: keine Stufe = D.
    (null, false, false, c),
    (null, false, true, c),
    (null, true, false, u),
    (null, true, true, u),
  ];
  for (final (level, locked, voice, expected) in table) {
    test('${level?.name ?? 'null'} gesperrt=$locked Stimme=$voice', () {
      expect(
        levelAccess(level, locked: locked, speakerRecognized: voice),
        expected,
      );
    });
  }

  group('gespeicherte Stufe', () {
    test('gültig', () {
      for (final l in SecurityLevel.values) {
        expect(SecurityLevel.effective(l.name, SecurityLevel.a), l);
      }
    });
    test('fehlt → Standard', () {
      expect(SecurityLevel.effective(null, SecurityLevel.b), SecurityLevel.b);
    });
    test('ungültig oder manipuliert → D, nie der Standard', () {
      for (final raw in ['', 'x', 'A', 'e', ' a', 'a ', 'null']) {
        expect(
          SecurityLevel.effective(raw, SecurityLevel.a),
          SecurityLevel.d,
          reason: raw,
        );
      }
    });
  });

  group('AccessContext', () {
    test('of entspricht levelAccess in jeder Zeile', () {
      for (final level in [null, ...SecurityLevel.values]) {
        for (final locked in [false, true]) {
          for (final voice in [false, true]) {
            expect(
              AccessContext(locked: locked, speakerRecognized: voice).of(level),
              levelAccess(level, locked: locked, speakerRecognized: voice),
              reason: '$level $locked $voice',
            );
          }
        }
      }
    });
    test('Gleichheit, Konstanten, Standard entsperrt', () {
      expect(const AccessContext(), AccessContext.unlocked);
      expect(AccessContext.unlocked.locked, isFalse);
      expect(AccessContext.lockedUnknownVoice.locked, isTrue);
      expect(AccessContext.lockedUnknownVoice.speakerRecognized, isFalse);
      expect(
        const AccessContext(locked: true).hashCode,
        AccessContext.lockedUnknownVoice.hashCode,
      );
      expect(AccessContext.unlocked, isNot(AccessContext.lockedUnknownVoice));
      expect(
        const AccessContext(locked: true, speakerRecognized: true),
        isNot(AccessContext.lockedUnknownVoice),
      );
      expect(AccessContext.lockedUnknownVoice.toString(), contains('true'));
    });
  });
}
