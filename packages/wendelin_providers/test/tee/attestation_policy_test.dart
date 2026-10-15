import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

StageResult _s(StageOutcome o) =>
    StageResult(AttestationStage.quote, o, o.name);

void main() {
  const policy = AttestationPolicy();
  const green = AttestationStatus.green;
  const yellow = AttestationStatus.yellow;
  const red = AttestationStatus.red;

  group('Richtlinie: Stufenergebnisse → Status', () {
    // (Ergebnisse, Sitzung, Quittung Versuch 1, 2, 3)
    final table = <(String, List<StageOutcome>, List<AttestationStatus>)>[
      ('alles bestanden', [StageOutcome.pass], [green, green, green, green]),
      (
        'Hinweis (warn) bleibt grün',
        [StageOutcome.pass, StageOutcome.warn],
        [green, green, green, green],
      ),
      (
        'nur protokolliert (info)',
        [StageOutcome.info],
        [green, green, green, green],
      ),
      (
        'eine Stufe rot',
        [StageOutcome.pass, StageOutcome.fail],
        [red, red, red, red],
      ),
      (
        'rot schlägt Netzfehler',
        [StageOutcome.unavailable, StageOutcome.fail],
        [red, red, red, red],
      ),
      // session, then receipt attempt 1, 2, ...
      (
        'Netzfehler: gelb, nach 6 Versuchen rot',
        [StageOutcome.unavailable],
        [yellow, yellow, yellow, yellow, yellow, yellow, red],
      ),
    ];
    for (final (name, outcomes, expected) in table) {
      test(name, () {
        final stages = [for (final o in outcomes) _s(o)];
        expect(policy.sessionStatus(stages), expected[0], reason: 'Sitzung');
        for (var attempt = 1; attempt < expected.length; attempt++) {
          expect(
            policy.receiptStatus(stages, attempt: attempt),
            expected[attempt],
            reason: 'Quittung Versuch $attempt',
          );
        }
      });
    }

    test('Hinweise stammen aus den warn-Stufen', () {
      expect(
        policy.notes([
          const StageResult(
            AttestationStage.tcb,
            StageOutcome.warn,
            'Hinweis A',
          ),
          _s(StageOutcome.pass),
        ]),
        ['Hinweis A'],
      );
    });

    test('Standard: sechs Quittungsversuche', () {
      expect(const AttestationPolicy().maxReceiptAttempts, 6);
    });

    test('maxReceiptAttempts ist einstellbar', () {
      const p = AttestationPolicy(maxReceiptAttempts: 1);
      expect(p.receiptStatus([_s(StageOutcome.unavailable)], attempt: 1), red);
    });
  });
}
