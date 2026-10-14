import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/src/tee/attestation_audit.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

void main() {
  test('zwei Instanzen mit fester Uhr erzeugen verschiedene Log-Ids', () {
    final settings = HttpSettings(
      clock: FixedClock(DateTime.utc(2026, 10, 14)),
    );
    final sink = InMemoryAttestationLog();
    final a = AttestationAudit('near', sink, settings);
    final b = AttestationAudit('near', sink, settings);
    final ids = {
      a.record(AttestationLogKind.session, AttestationStatus.green, const []),
      b.record(AttestationLogKind.session, AttestationStatus.green, const []),
    };
    expect(ids, hasLength(2));
    expect(sink.entries.map((e) => e.logId).toSet(), ids);
  });
}
