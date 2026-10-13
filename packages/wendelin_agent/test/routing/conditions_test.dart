import 'package:test/test.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'fixtures.dart';

void main() {
  void table(
    String name,
    Condition condition,
    List<(RoutingContext, bool)> cases,
  ) {
    group(name, () {
      for (final (i, (ctx, expected)) in cases.indexed) {
        test('#$i „${ctx.input.text}“ → $expected', () {
          expect(condition.evaluate(ctx) != null, expected);
        });
      }
    });
  }

  table('keyword', KeywordCondition(['privat', 'denk gründlich nach']), [
    (ctxFor('Das ist PRIVAT.'), true),
    (ctxFor('privat'), true),
    (ctxFor('Denk GRUENDLICH nach'), false), // ue is not folded to u
    (ctxFor('denk, gründlich – nach!'), true),
    (ctxFor('Privatsphäre'), false),
    (ctxFor('unprivat'), false),
    (ctxFor(''), false),
  ]);

  table('prefix', PrefixCondition(['Claude', 'hey Fable']), [
    (ctxFor('Claude, hallo'), true),
    (ctxFor('...claude hallo'), true),
    (ctxFor('Hey, Fable: los'), true),
    (ctxFor('Fable, los'), false),
    (ctxFor('Hallo Claude'), false),
    (ctxFor('Claudette'), false),
    (ctxFor('Claude'), true),
  ]);

  table('regex', RegExpTestHelper.condition, [
    (ctxFor('Termin um 14 Uhr'), true),
    (ctxFor('TERMIN, um 9 uhr!'), true),
    (ctxFor('Termin morgen'), false),
  ]);

  table('language', LanguageCondition(['fr', 'EN']), [
    (ctxFor('x', language: 'fr-CH'), true),
    (ctxFor('x', language: 'en_US'), true),
    (ctxFor('x', language: 'de'), false),
    (ctxFor('x'), false),
  ]);

  table('sttConfidence', const SttConfidenceCondition(0.6), [
    (ctxFor('x', sttConfidence: 0.59), true),
    (ctxFor('x', sttConfidence: 0.6), false),
    (ctxFor('x', sttConfidence: 0.9), false),
    (ctxFor('x'), false),
  ]);

  table('inputLength', const InputLengthCondition(5), [
    (ctxFor('123456'), true),
    (ctxFor('12345'), false),
    (ctxFor('  12345  '), false),
    (ctxFor('äöüßé1'), true),
  ]);

  final image = ImageBlock(mediaType: 'image/png', bytes: const [0]);
  table('hasImage', const HasImageCondition(), [
    (ctxFor('x', images: [image]), true),
    (ctxFor('x'), false),
  ]);

  for (final (state, expected) in [
    (NetworkState.offline, [true, false, false]),
    (NetworkState.online, [false, true, true]),
    (NetworkState.metered, [false, false, true]),
  ]) {
    table('network ${state.name}', NetworkCondition(state), [
      (ctxFor('x', network: NetworkState.offline), expected[0]),
      (ctxFor('x', network: NetworkState.online), expected[1]),
      (ctxFor('x', network: NetworkState.metered), expected[2]),
    ]);
  }

  group('timeWindow', () {
    // 2026-10-16 is a Friday, 2026-10-17 a Saturday, 2026-10-19 a Monday.
    DateTime at(int day, int h, [int m = 0]) => DateTime(2026, 10, day, h, m);
    final overnight = TimeWindowCondition(
      days: {DateTime.friday},
      start: 22 * 60,
      end: 6 * 60,
    );
    final office = TimeWindowCondition(
      days: {for (var d = 1; d <= 5; d++) d},
      start: 9 * 60,
      end: 17 * 60 + 30,
    );
    final sundayNight = TimeWindowCondition(
      days: {DateTime.sunday},
      start: 23 * 60,
      end: 60,
    );
    final allDay = TimeWindowCondition(
      days: {DateTime.saturday},
      start: 0,
      end: 0,
    );
    final everyNight = TimeWindowCondition(start: 22 * 60, end: 6 * 60);

    final cases = <(String, TimeWindowCondition, DateTime, bool)>[
      ('Fr 22:00 start', overnight, at(16, 22), true),
      ('Fr 21:59 before', overnight, at(16, 21, 59), false),
      ('Sa 03:00 after midnight', overnight, at(17, 3), true),
      ('Sa 05:59 last minute', overnight, at(17, 5, 59), true),
      ('Sa 06:00 end exclusive', overnight, at(17, 6), false),
      ('Sa 22:00 wrong start day', overnight, at(17, 22), false),
      ('Fr 03:00 belongs to Thursday', overnight, at(16, 3), false),
      ('Mi 10:00 office', office, at(14, 10), true),
      ('Mi 17:30 office end', office, at(14, 17, 30), false),
      ('Sa 10:00 weekend', office, at(17, 10), false),
      ('So 23:30', sundayNight, at(18, 23, 30), true),
      ('Mo 00:30 week boundary', sundayNight, at(19, 0, 30), true),
      ('Mo 01:00 end', sundayNight, at(19, 1), false),
      ('Sa all day', allDay, at(17, 13), true),
      ('So not all day', allDay, at(18, 13), false),
      ('every day 23:00', everyNight, at(14, 23), true),
      ('every day 12:00', everyNight, at(14, 12), false),
    ];
    for (final (name, c, now, expected) in cases) {
      test('$name → $expected', () {
        final clock = FixedClock(now);
        expect(c.evaluate(ctxFor('x', now: clock.now())) != null, expected);
      });
    }

    test('invalid times and days are problems', () {
      expect(overnight.problem, isNull);
      expect(TimeWindowCondition(start: -1, end: 0).problem, isNotNull);
      expect(TimeWindowCondition(start: 0, end: 1440).problem, isNotNull);
      expect(
        TimeWindowCondition(days: {0}, start: 0, end: 1).problem,
        'Ungültiger Wochentag.',
      );
    });
  });

  group('needsTool', () {
    final c = const NeedsToolCondition('obsidian.edit');
    test('asks the matcher with the normalized text', () {
      final m = FakeToolCategoryMatcher({'obsidian.edit'});
      expect(c.evaluate(ctxFor('Schreib, die Notiz!', matcher: m)), isNotNull);
      expect(m.asked, [('schreib die notiz', 'obsidian.edit')]);
    });
    test('no match without the category', () {
      final m = FakeToolCategoryMatcher({'calendar'});
      expect(c.evaluate(ctxFor('x', matcher: m)), isNull);
    });
  });

  table('privacy (default words)', PrivacyCondition(), [
    (ctxFor('Das ist privat'), true),
    (ctxFor('Private Notiz'), true),
    (ctxFor("C'est privé"), true),
    (ctxFor('vertraulich: Gehalt'), true),
    (ctxFor('Privatsphäre'), false),
    (ctxFor('Hallo'), false),
  ]);

  test('privacy match marks the route private, keyword does not', () {
    expect(PrivacyCondition().evaluate(ctxFor('privat'))!.private, isTrue);
    expect(
      KeywordCondition(['privat']).evaluate(ctxFor('privat'))!.private,
      isFalse,
    );
  });

  group('and / or / not nested', () {
    final claude = PrefixCondition(['Claude']);
    final priv = PrivacyCondition();
    final offline = const NetworkCondition(NetworkState.offline);
    // (Claude-Präfix oder privat) und nicht offline
    final tree = AndCondition([
      OrCondition([claude, priv]),
      NotCondition(offline),
    ]);
    // nicht (Claude-Präfix und nicht privat)
    final negated = NotCondition(AndCondition([claude, NotCondition(priv)]));

    final cases = <(String, Condition, String, NetworkState, bool)>[
      ('tree', tree, 'Claude, hallo', NetworkState.online, true),
      ('tree', tree, 'das ist privat', NetworkState.online, true),
      ('tree', tree, 'Claude, privat', NetworkState.offline, false),
      ('tree', tree, 'hallo', NetworkState.online, false),
      ('negated', negated, 'Claude, hallo', NetworkState.online, false),
      ('negated', negated, 'Claude, privat', NetworkState.online, true),
      ('negated', negated, 'hallo', NetworkState.online, true),
      ('empty and', AndCondition(const []), 'x', NetworkState.online, true),
      ('empty or', OrCondition(const []), 'x', NetworkState.online, false),
    ];
    for (final (name, c, text, net, expected) in cases) {
      test('$name „$text“ ${net.name} → $expected', () {
        expect(c.evaluate(ctxFor(text, network: net)) != null, expected);
      });
    }

    test('and collects triggers and privacy of all parts', () {
      final m = AndCondition([claude, priv])
          .evaluate(ctxFor('Claude, privat'))!;
      expect(m.triggers, hasLength(2));
      expect(m.private, isTrue);
    });

    test('or takes the first matching branch', () {
      final m = OrCondition([priv, claude]).evaluate(ctxFor('Claude, hallo'))!;
      expect(m.private, isFalse);
      expect(m.triggers, [const TriggerSpan(0, 6)]);
    });

    test('not hides privacy and triggers', () {
      final m = NotCondition(claude).evaluate(ctxFor('privat'))!;
      expect(m.triggers, isEmpty);
      expect(NotCondition(priv).marksPrivate, isFalse);
      expect(OrCondition([claude, priv]).marksPrivate, isTrue);
      expect(AndCondition([priv]).marksPrivate, isTrue);
      expect(claude.marksPrivate, isFalse);
    });

    test('trigger words and traversal', () {
      final c = AndCondition([
        claude,
        OrCondition([
          KeywordCondition(['Sonnet']),
          NotCondition(PrefixCondition(['nie'])),
        ]),
        priv,
      ]);
      expect(c.triggerWords, ['Claude', 'Sonnet']);
      expect(c.all, hasLength(7));
    });
  });

  group('regex protection', () {
    test('patterns over 200 characters are invalid', () {
      final ok = RegexCondition('a' * 200);
      final tooLong = RegexCondition('a' * 201);
      expect(ok.problem, isNull);
      expect(tooLong.problem, contains('200'));
      expect(tooLong.evaluate(ctxFor('a' * 300)), isNull);
    });

    test('broken patterns are invalid, not a crash', () {
      final c = RegexCondition('(unclosed');
      expect(c.problem, startsWith('Ungültiger regulärer Ausdruck'));
      expect(c.evaluate(ctxFor('(unclosed')), isNull);
    });

    test('only the first 300 characters are searched', () {
      final c = RegexCondition('ziel');
      final near = '${'x ' * 148}ziel';
      final far = '${'x ' * 149}ziel';
      expect(c.evaluate(ctxFor(near)), isNotNull);
      expect(c.evaluate(ctxFor(far)), isNull);
    });

    final unsafe = <String>[
      r'(a+)+$',
      r'(a*)*b',
      r'(a|aa)*$',
      r'(x+x+)+y',
      r'((ab)*c)+',
      r'(\w+\s?){2,}',
      r'(a)\1',
      r'(?<x>a)\k<x>',
      r'\w*\w*\w*x',
      r'.*a.*b.+c',
      r'a{2,}b{1,9}c*',
    ];
    for (final p in unsafe) {
      test('„$p“ is rejected', () {
        final c = RegexCondition(p);
        expect(c.problem, isNotNull);
        expect(c.evaluate(ctxFor('a' * 26)), isNull);
      });
    }

    final safe = <String>[
      r'^claude\b',
      r'(?:ab)+c',
      r'(claude|fable) bitte',
      r'(a+)?b',
      r'[(+*]+x',
      r'\(a+\)+',
      r'\w*\w*x',
      r'a{2}b{3}c+d*',
    ];
    for (final p in safe) {
      test('„$p“ is allowed', () => expect(RegexCondition(p).problem, isNull));
    }

    test('allowed patterns stay fast on the longest input', () {
      final watch = Stopwatch()..start();
      for (final p in safe) {
        RegexCondition(p).evaluate(ctxFor('a' * 5000));
      }
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('an empty match has no trigger', () {
      final m = RegexCondition('^').evaluate(ctxFor('Hallo'))!;
      expect(m.triggers, isEmpty);
    });
  });

  test('equality and hash codes', () {
    final pairs = <(Condition, Condition, Condition)>[
      (KeywordCondition(['a']), KeywordCondition(['a']), KeywordCondition([])),
      (PrefixCondition(['a']), PrefixCondition(['a']), PrefixCondition(['b'])),
      (RegexCondition('a'), RegexCondition('a'), RegexCondition('b')),
      (
        LanguageCondition(['de']),
        LanguageCondition(['de']),
        LanguageCondition(['fr']),
      ),
      (
        const SttConfidenceCondition(0.5),
        const SttConfidenceCondition(0.5),
        const SttConfidenceCondition(0.4),
      ),
      (
        const InputLengthCondition(1),
        const InputLengthCondition(1),
        const InputLengthCondition(2),
      ),
      (
        const NetworkCondition(NetworkState.online),
        const NetworkCondition(NetworkState.online),
        const NetworkCondition(NetworkState.offline),
      ),
      (
        TimeWindowCondition(days: {1, 2}, start: 1, end: 2),
        TimeWindowCondition(days: {2, 1}, start: 1, end: 2),
        TimeWindowCondition(days: {1}, start: 1, end: 2),
      ),
      (
        const NeedsToolCondition('a'),
        const NeedsToolCondition('a'),
        const NeedsToolCondition('b'),
      ),
      (PrivacyCondition(), PrivacyCondition(), PrivacyCondition(['x'])),
      (
        AndCondition([const HasImageCondition()]),
        AndCondition([const HasImageCondition()]),
        OrCondition([const HasImageCondition()]),
      ),
      (
        OrCondition([const HasImageCondition()]),
        OrCondition([const HasImageCondition()]),
        OrCondition(const []),
      ),
      (
        const NotCondition(HasImageCondition()),
        const NotCondition(HasImageCondition()),
        const HasImageCondition(),
      ),
    ];
    for (final (a, b, c) in pairs) {
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    }
    expect(const HasImageCondition().hashCode, 'hasImage'.hashCode);
  });
}

abstract final class RegExpTestHelper {
  static final condition = RegexCondition(r'^termin um \d+ uhr$');
}
