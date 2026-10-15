import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/costs.dart';
import 'package:wendelin/di/session_manager.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart' show SessionOrigin;

ProviderProfile _profile({int? budget, double? warn}) => ProviderProfile(
  id: 'claude',
  name: 'Claude',
  type: ProviderType.anthropic,
  defaultModel: 'claude-haiku-4-5',
  privacy: PrivacyLevel.standard,
  authMethod: const ApiKeyAuth('provider.claude'),
  budgetMonthly: budget,
  warnThreshold: warn,
);

void main() {
  group('SessionManager', () {
    test('gleiche Sitzung bis zur Inaktivität, dann Ende und neue', () async {
      final clock = FixedClock(DateTime(2026, 10, 13, 8));
      final storage = openInMemoryStorage(clock: clock);
      final ended = <String>[];
      final m = SessionManager(
        conversations: storage.conversations,
        clock: clock,
        onSessionEnd: ended.add,
      );
      addTearDown(m.dispose);
      final a = await m.ensure();
      await storage.conversations.append(a, Message.user('x'));
      expect(await m.ensure(), a);
      clock.advance(const Duration(minutes: 6));
      final b = await m.ensure();
      expect(b, isNot(a));
      expect(ended, [a]);
    });

    test('Timer beendet die Sitzung nach 5 min ohne Aktivität', () {
      fakeAsync((async) {
        final clock = FixedClock(DateTime(2026, 10, 13, 8));
        final storage = openInMemoryStorage(clock: clock);
        final ended = <String>[];
        final m = SessionManager(
          conversations: storage.conversations,
          clock: clock,
          onSessionEnd: ended.add,
        );
        String? id;
        m.ensure().then((v) => id = v);
        async.flushMicrotasks();
        expect(id, isNotNull);
        async.elapse(const Duration(minutes: 4));
        m.touch();
        async.elapse(const Duration(minutes: 4));
        expect(ended, isEmpty, reason: 'Aktivität verlängert');
        async.elapse(const Duration(minutes: 1, seconds: 1));
        expect(ended, [id]);
        expect(m.currentId, isNull);
        m.end();
        expect(ended, [id], reason: 'kein zweites Ende');
      });
    });

    test('startNew beendet die alte Sitzung', () async {
      final storage = openInMemoryStorage();
      final ended = <String>[];
      final m = SessionManager(
        conversations: storage.conversations,
        clock: const SystemClock(),
        onSessionEnd: ended.add,
      );
      addTearDown(m.dispose);
      final a = await m.ensure();
      final b = await m.startNew();
      expect(b, isNot(a));
      expect(ended, [a]);
      expect(m.currentId, b);
    });
  });

  group('SessionManager frischer Aufruf (WP67)', () {
    test(
      'beginFresh: nächste Sitzung neu, Overlay verdrängt App nicht',
      () async {
        final clock = FixedClock(DateTime(2026, 10, 15, 8));
        final storage = openInMemoryStorage(clock: clock);
        SessionManager make() => SessionManager(
          conversations: storage.conversations,
          clock: clock,
          onSessionEnd: (_) {},
        );
        final app = make();
        final overlay = make();
        addTearDown(app.dispose);
        addTearDown(overlay.dispose);
        final a = await app.ensure();
        await storage.conversations.append(a, Message.user('Glocken'));
        overlay.beginFresh();
        final o = await overlay.ensure();
        expect(o, isNot(a), reason: 'Overlay startet leer');
        expect(
          await overlay.ensure(),
          o,
          reason: 'Folgefrage: gleiche Sitzung',
        );
        await storage.conversations.append(o, Message.user('Wetter'));
        expect(await app.ensure(), a, reason: 'App-Chat bleibt in seiner');
      },
    );

    test(
      'App-ensure nach frischer Overlay-Sitzung landet nicht darin',
      () async {
        final clock = FixedClock(DateTime(2026, 10, 15, 8));
        final storage = openInMemoryStorage(clock: clock);
        SessionManager make(SessionOrigin origin) => SessionManager(
          conversations: storage.conversations,
          clock: clock,
          onSessionEnd: (_) {},
          origin: origin,
        );
        final overlay = make(SessionOrigin.overlay);
        addTearDown(overlay.dispose);
        overlay.beginFresh();
        final o = await overlay.ensure();
        await storage.conversations.append(o, Message.user('Glocken'));
        // App-Kaltstart: neuer Manager ohne eigene Sitzung.
        final app = make(SessionOrigin.app);
        addTearDown(app.dispose);
        final a = await app.ensure();
        expect(a, isNot(o));
        expect(
          (await storage.conversations.session(a))?.origin,
          SessionOrigin.app,
        );
        expect(
          (await storage.conversations.session(o))?.origin,
          SessionOrigin.overlay,
        );
      },
    );
  });

  group('RepositoryBudgetGuard', () {
    Future<BudgetCheck> check({
      int? budget,
      double? warn,
      int spent = 0,
      bool known = true,
    }) async {
      final storage = openInMemoryStorage();
      if (known) {
        await storage.providerProfiles.save(
          _profile(budget: budget, warn: warn),
        );
      }
      if (spent > 0) {
        await storage.usage.record(
          sessionId: 's',
          profileId: 'claude',
          modelId: 'm',
          usage: Usage.zero,
          costMicros: spent,
        );
      }
      return RepositoryBudgetGuard(
        profiles: storage.providerProfiles,
        usage: storage.usage,
      ).check('claude');
    }

    test('ohne Profil oder Budget: ok', () async {
      expect((await check(known: false)).status, BudgetStatus.ok);
      expect((await check(spent: 999)).status, BudgetStatus.ok);
    });

    test(
      'unter der Warnschwelle: ok; ab Schwelle: warn; ab Budget: block',
      () async {
        expect(
          (await check(budget: 1000, warn: 0.8, spent: 799)).status,
          BudgetStatus.ok,
        );
        final warn = await check(budget: 1000, warn: 0.8, spent: 800);
        expect(warn.status, BudgetStatus.warn);
        expect(warn.spentMicros, 800);
        expect(warn.budgetMicros, 1000);
        expect(
          (await check(budget: 1000, warn: 0.8, spent: 999)).status,
          BudgetStatus.warn,
        );
        final block = await check(budget: 1000, warn: 0.8, spent: 1000);
        expect(block.status, BudgetStatus.block);
        expect(block.spentMicros, 1000);
      },
    );

    test('ohne Warnschwelle nur Sperre', () async {
      expect((await check(budget: 1000, spent: 999)).status, BudgetStatus.ok);
      expect(
        (await check(budget: 1000, spent: 1001)).status,
        BudgetStatus.block,
      );
    });
  });

  test('CatalogCostEstimator rechnet mit dem Modellkatalog', () {
    const usage = Usage(inputTokens: 1000000);
    final estimator = CatalogCostEstimator(
      CostCalculator(ModelCatalog.builtIn()),
    );
    final cost = estimator.estimateMicros(
      profileId: 'p',
      modelId: 'claude-haiku-4-5',
      usage: usage,
    );
    expect(
      cost,
      CostCalculator(ModelCatalog.builtIn())
          .costMicros('claude-haiku-4-5', usage),
    );
    expect(cost, greaterThan(0));
    expect(
      estimator.estimateMicros(
        profileId: 'p',
        modelId: 'unbekannt',
        usage: usage,
      ),
      isNull,
    );
  });

  test('todayCostMicros summiert nur heute', () async {
    final clock = FixedClock(DateTime(2026, 10, 13, 8));
    final storage = openInMemoryStorage(clock: clock);
    Future<void> rec(DateTime at, int micros) => storage.usage.record(
      sessionId: 's',
      profileId: 'p',
      modelId: 'm',
      usage: Usage.zero,
      costMicros: micros,
      at: at,
    );
    await rec(DateTime(2026, 10, 12, 23, 59), 5000);
    await rec(DateTime(2026, 10, 13, 0, 1), 10000);
    await rec(DateTime(2026, 10, 13, 7), 20000);
    expect(await todayCostMicros(storage.usage, clock.now()), 30000);
  });
}
