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
}
