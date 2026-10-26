// WP151: Buchführung der Kandidaten (Wortende bleibt beim Wiedereinplanen).
import 'package:test/test.dart';
import 'package:wendelin_voice/src/wake/barge_candidates.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  test('Kandidat aus dem Cooldown behält das Wortende (pendingLoud)', () {
    final c = BargeCandidates()..defer(BargeInKeyword.wake, 0.8, 1000, 900);
    c.promoteAfterCooldown(1200, 40000, 100);
    expect(c.pendingKind, BargeInKeyword.wake);
    expect(c.pendingLoud, 900);
    expect(c.takePending(), BargeInKeyword.wake);
    expect(c.checkedLoud, 900);
  });

  test('ohne gemerktes Wortende bleibt pendingLoud leer', () {
    final c = BargeCandidates()..defer(BargeInKeyword.wake, 0.8, 1000, -1);
    c.promoteAfterCooldown(1200, 40000, 100);
    expect(c.pendingKind, BargeInKeyword.wake);
    expect(c.pendingLoud, -1);
  });

  test(
    'Cooldown endet bei wartendem stärkerem Kandidaten: Schnitt bleibt -1',
    () {
      // Echo D zurückgestellt, dann echter Ruf S (stärker) sofort pending
      // (pendingLoud = -1); beim Cooldown-Ende darf D das Wortende nicht
      // überschreiben.
      final c = BargeCandidates()
        ..defer(BargeInKeyword.wake, 0.6, 10000, 9000)
        ..addPending(BargeInKeyword.wake, 0.9, 42800);
      c.promoteAfterCooldown(32000, 40000, 12800);
      expect(c.takePending(), BargeInKeyword.wake);
      expect(c.checkedLoud, -1);
      expect(c.checkedScore, 0.9);
    },
  );
}
