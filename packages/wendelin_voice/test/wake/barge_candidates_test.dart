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

  // Invariante (WP151 Runde 3): der Schnitt (loud) gehört immer zum stärksten
  // wartenden Kandidaten. Echo = Wortende 500, Ruf = Wortende -1 (letztes
  // Sprechen) bzw. 900 aus dem Cooldown.
  group('Übergänge: Wortende gehört zum wartenden Kandidaten', () {
    const w = BargeInKeyword.wake;
    // Zustand vorher: wartender Kandidat (Score, Wortende) oder keiner.
    // Ankunft: direkt (frei) oder aus dem Cooldown (deferred, Wortende 900).
    final cases =
        <
          ({
            String name,
            (double, int)? waiting,
            bool viaCooldown,
            double score,
            int wantLoud,
            double wantScore,
          })
        >[
          (
            name: 'frei, Echo direkt',
            waiting: null,
            viaCooldown: false,
            score: 0.7,
            wantLoud: -1,
            wantScore: 0.7,
          ),
          (
            name: 'frei, Cooldown-Ende',
            waiting: null,
            viaCooldown: true,
            score: 0.7,
            wantLoud: 900,
            wantScore: 0.7,
          ),
          (
            name: 'Echo wartet, Ruf direkt stärker',
            waiting: (0.7, 500),
            viaCooldown: false,
            score: 0.95,
            wantLoud: -1,
            wantScore: 0.95,
          ),
          (
            name: 'Echo wartet, Echo direkt schwächer',
            waiting: (0.7, 500),
            viaCooldown: false,
            score: 0.5,
            wantLoud: 500,
            wantScore: 0.7,
          ),
          (
            name: 'Echo wartet, Cooldown-Ende stärker',
            waiting: (0.7, 500),
            viaCooldown: true,
            score: 0.95,
            wantLoud: 900,
            wantScore: 0.95,
          ),
          (
            name: 'Echo wartet, Cooldown-Ende schwächer',
            waiting: (0.7, 500),
            viaCooldown: true,
            score: 0.5,
            wantLoud: 500,
            wantScore: 0.7,
          ),
          (
            name: 'Ruf wartet, Echo direkt schwächer',
            waiting: (0.9, -1),
            viaCooldown: false,
            score: 0.5,
            wantLoud: -1,
            wantScore: 0.9,
          ),
          (
            name: 'Ruf wartet, Cooldown-Ende schwächer',
            waiting: (0.9, -1),
            viaCooldown: true,
            score: 0.5,
            wantLoud: -1,
            wantScore: 0.9,
          ),
          (
            name: 'Ruf wartet, Cooldown-Ende stärker',
            waiting: (0.9, -1),
            viaCooldown: true,
            score: 0.99,
            wantLoud: 900,
            wantScore: 0.99,
          ),
        ];
    for (final c in cases) {
      test(c.name, () {
        final k = BargeCandidates();
        final wt = c.waiting;
        if (wt != null) k.addPending(w, wt.$1, 5000, loud: wt.$2);
        if (c.viaCooldown) {
          k
            ..defer(w, c.score, 1000, 900)
            ..promoteAfterCooldown(1200, 40000, 100);
        } else {
          k.addPending(w, c.score, 5000);
        }
        expect(k.pendingLoud, c.wantLoud);
        expect(k.pendingScore, c.wantScore);
        k.takePending();
        expect(k.checkedLoud, c.wantLoud);
        expect(k.pendingKind, isNull);
        expect(k.pendingLoud, -1);
      });
    }

    // Während der Prüfung: das Wortende folgt dem stärksten Zurückgestellten.
    for (final c in [
      (
        name: 'Prüfung, Echo dann Ruf stärker: Ruf-Wortende',
        first: 0.8,
        second: 0.96,
        wantLoud: 2000,
      ),
      (
        name: 'Prüfung, Ruf dann Echo schwächer: Ruf-Wortende',
        first: 0.96,
        second: 0.8,
        wantLoud: 1000,
      ),
    ]) {
      test(c.name, () {
        final k = BargeCandidates()
          ..checkedScore = 0.85
          ..defer(w, c.first, 1000, 1000)
          ..defer(w, c.second, 2000, 2000);
        k.rescheduleAfterReject(
          fed: 3000,
          blockedUntil: 9000,
          settle: 100,
          ring: 80000,
          margin: 0.05,
        );
        expect(k.pendingLoud, c.wantLoud);
        // Cooldown: ein stärkerer direkter Ruf übernimmt Score und Schnitt.
        k.addPending(w, 0.99, 9500);
        expect(k.pendingLoud, -1);
        expect(k.pendingScore, 0.99);
      });
    }

    test('Reviewer-Probe: Echo nach Verwerfen, Ruf im Cooldown (-1)', () {
      final k = BargeCandidates()
        ..checkedScore = 0.85
        ..defer(w, 0.8, 17600, 17600);
      k.rescheduleAfterReject(
        fed: 24000,
        blockedUntil: 48000,
        settle: 12800,
        ring: 80000,
        margin: 0.05,
      );
      k.addPending(w, 0.96, 46400);
      k.takePending();
      expect(k.checkedLoud, -1);
    });

    test('clear: kein Rest von Kandidat und Wortende', () {
      final k = BargeCandidates()..addPending(w, 0.7, 5000, loud: 500);
      k.clear();
      expect(k.pending, isNull);
      expect(k.pendingLoud, -1);
      expect(k.pendingScore, 0);
    });
  });
}
