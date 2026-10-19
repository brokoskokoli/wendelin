import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

FakeIntegration _integration(
  String id,
  List<String> tools, {
  bool sensitive = false,
  Availability availability = Availability.yes,
  List<String> missingSteps = const [],
  Set<AppPlatform> platforms = const {AppPlatform.android, AppPlatform.ios},
  String? displayName,
}) => FakeIntegration(
  id: id,
  displayName: displayName,
  tools: [
    for (final t in tools)
      FakeTool(name: '${id}__$t', description: 'Tool $t von $id'),
  ],
  sensitive: sensitive,
  availability: availability,
  missingSteps: missingSteps,
  platforms: platforms,
);

final class _ThrowingIntegration implements Integration {
  final _inner = FakeIntegration(id: 'boom', tools: const []);

  @override
  String get id => _inner.id;
  @override
  String get displayName => _inner.displayName;
  @override
  String get iconId => _inner.iconId;
  @override
  Set<AppPlatform> get platforms => _inner.platforms;
  @override
  bool get sensitive => false;
  @override
  List<SetupStep> get setup => const [];
  @override
  List<Tool> get tools => const [];
  @override
  Future<SetupState> setupState() => _inner.setupState();
  @override
  Future<Availability> checkAvailability() async =>
      throw StateError('Paketprüfung kaputt');
}

ToolContext _ctx(String session) => ToolContext(
  sessionId: session,
  clock: const SystemClock(),
  locale: 'de-DE',
  timeZone: 'Europe/Berlin',
);

ToolCatalog _cat(
  ToolRegistry r, {
  PrivacyLevel level = PrivacyLevel.local,
  String session = 's1',
}) => r.catalogFor(level, sessionId: session);

List<String> _names(List<ToolSpec> specs) => [for (final s in specs) s.name];

void main() {
  group('Registrierung', () {
    test('lehnt doppelte Integration ab', () async {
      final r = ToolRegistry();
      await r.registerIntegration(_integration('cal', ['list']));
      expect(
        () => r.registerIntegration(_integration('cal', ['other'])),
        throwsArgumentError,
      );
    });

    test('lehnt ungültige Tool-Namen ab', () async {
      final r = ToolRegistry();
      final bad = FakeIntegration(
        id: 'x',
        tools: [FakeTool(name: 'x.list')],
      );
      await expectLater(r.registerIntegration(bad), throwsArgumentError);
      expect(r.integrations, isEmpty);
    });

    test('lehnt ungültige Integrations-Id ab', () async {
      final r = ToolRegistry();
      await expectLater(
        r.registerIntegration(FakeIntegration(id: 'mit leer', tools: [])),
        throwsArgumentError,
      );
    });

    test('lehnt Duplikate innerhalb und zwischen Integrationen ab', () async {
      final r = ToolRegistry();
      await expectLater(
        r.registerIntegration(
          FakeIntegration(
            id: 'a',
            tools: [
              FakeTool(name: 'a__x'),
              FakeTool(name: 'a__x'),
            ],
          ),
        ),
        throwsArgumentError,
      );
      await r.registerIntegration(
        FakeIntegration(
          id: 'b',
          tools: [FakeTool(name: 'shared__x')],
        ),
      );
      await expectLater(
        r.registerIntegration(
          FakeIntegration(
            id: 'c',
            tools: [FakeTool(name: 'shared__x')],
          ),
        ),
        throwsArgumentError,
      );
      expect([for (final i in r.integrations) i.id], ['b']);
    });

    test('lehnt den reservierten Namen tools__search ab', () async {
      final r = ToolRegistry();
      await expectLater(
        r.registerIntegration(
          FakeIntegration(
            id: 'tools',
            tools: [FakeTool(name: 'tools__search')],
          ),
        ),
        throwsArgumentError,
      );
    });

    test('unregister entfernt Tools; Name wieder frei', () async {
      final r = ToolRegistry();
      await r.registerIntegration(_integration('cal', ['list']), enabled: true);
      r
        ..setToolEnabled('cal__list', enabled: false)
        ..unregister('cal')
        ..unregister('cal'); // no-op
      expect(_cat(r).activeSpecs(), isEmpty);
      expect(_cat(r).lookup('cal__list'), isNull);
      await r.registerIntegration(_integration('cal', ['list']), enabled: true);
      expect(r.isToolEnabled('cal__list'), isTrue);
    });

    test('unbekannte Ids werfen', () {
      final r = ToolRegistry();
      expect(() => r.info('nix'), throwsArgumentError);
      expect(() => r.setEnabled('nix', enabled: true), throwsArgumentError);
      expect(
        () => r.setToolEnabled('nix__a', enabled: true),
        throwsArgumentError,
      );
      expect(() => r.reportError('nix', 'x'), throwsArgumentError);
    });
  });

  group('Status', () {
    test('Statustabelle', () {
      IntegrationStatus s(bool a, bool e, bool err, bool setup) =>
          IntegrationInfo.deriveStatus(
            available: a,
            enabled: e,
            hasError: err,
            setupComplete: setup,
          );
      expect(s(false, true, true, false), IntegrationStatus.unavailable);
      expect(s(true, false, true, false), IntegrationStatus.available);
      expect(s(true, true, true, false), IntegrationStatus.error);
      expect(s(true, true, false, false), IntegrationStatus.setupRequired);
      expect(s(true, true, false, true), IntegrationStatus.active);
    });

    test('nur optionale Schritte offen: aktiv', () async {
      final r = ToolRegistry();
      final web = FakeIntegration(
        id: 'web',
        tools: [FakeTool(name: 'web__fetch')],
        setup: const [
          SetupStep(
            id: 'search',
            kind: SetupStepKind.config,
            label: 'Suchdienst',
            optional: true,
          ),
          SetupStep(id: 'net', kind: SetupStepKind.permission, label: 'Netz'),
        ],
        missingSteps: ['search'],
      );
      await r.registerIntegration(web, enabled: true);
      expect(r.status('web'), IntegrationStatus.active);
      expect(r.info('web').setup.missingSteps, ['search']);
      expect(
        r
            .catalogFor(PrivacyLevel.standard, sessionId: 's')
            .activeSpecs()
            .map((s) => s.name),
        ['web__fetch'],
      );
      web.missingSteps = ['search', 'net'];
      await r.refresh('web');
      expect(r.status('web'), IntegrationStatus.setupRequired);
    });

    test('Verfügbarkeit, Aktivierung, Setup und Fehler', () async {
      final r = ToolRegistry();
      final cal = _integration('cal', ['list'], missingSteps: ['perm']);
      await r.registerIntegration(cal);
      expect(r.status('cal'), IntegrationStatus.available);
      r.setEnabled('cal', enabled: true);
      expect(r.status('cal'), IntegrationStatus.setupRequired);
      expect(r.info('cal').setup.missingSteps, ['perm']);
      cal.missingSteps = [];
      await r.refresh('cal');
      expect(r.status('cal'), IntegrationStatus.active);
      r.reportError('cal', 'Token abgelaufen');
      expect(r.status('cal'), IntegrationStatus.error);
      expect(r.info('cal').error, 'Token abgelaufen');
      expect(_cat(r).activeSpecs(), isEmpty, reason: 'Tools pausiert');
      expect(r.info('cal').errorKind, isNull, reason: 'ohne Art gemeldet');
      r.reportError('cal', 'x', kind: PortErrorKind.permissionDenied);
      expect(r.info('cal').errorKind, PortErrorKind.permissionDenied);
      r.reportError('cal', 'y');
      expect(r.info('cal').errorKind, isNull, reason: 'neue Meldung ersetzt');
      r.reportError('cal', 'z', kind: PortErrorKind.failed);
      r.clearError('cal');
      expect(r.status('cal'), IntegrationStatus.active);
      expect(
        r.info('cal').errorKind,
        isNull,
        reason: 'clearError setzt zurück',
      );
      cal.availability = const Availability(
        available: false,
        reason: 'App fehlt',
      );
      await r.refresh();
      expect(r.status('cal'), IntegrationStatus.unavailable);
      expect(r.info('cal').availability.reason, 'App fehlt');
      expect(r.info('cal').toString(), contains('unavailable'));
    });

    test('falsche Plattform: nicht verfügbar, ohne Prüfung', () async {
      final r = ToolRegistry(platform: AppPlatform.ios);
      final only = _integration(
        'sms',
        ['send'],
        platforms: {AppPlatform.android},
      );
      await r.registerIntegration(only, enabled: true);
      expect(r.status('sms'), IntegrationStatus.unavailable);
      expect(only.availabilityChecks, 0);
      expect(_cat(r).activeSpecs(), isEmpty);
    });

    test('Prüfung wirft → Fehlerstatus, wenn aktiviert', () async {
      final r = ToolRegistry();
      await r.registerIntegration(_ThrowingIntegration());
      expect(r.status('boom'), IntegrationStatus.available);
      r.setEnabled('boom', enabled: true);
      expect(r.status('boom'), IntegrationStatus.error);
      expect(r.info('boom').error, contains('Paketprüfung kaputt'));
    });

    test('vor der ersten Prüfung nicht verfügbar', () {
      final r = ToolRegistry();
      unawaited(r.registerIntegration(_integration('cal', ['a'])));
      expect(r.status('cal'), IntegrationStatus.unavailable);
      expect(r.info('cal').availability.reason, 'Wird geprüft');
    });
  });

  group('activeSpecs', () {
    test('nur aktive Integrationen und Tools, nach Name sortiert', () async {
      final r = ToolRegistry();
      await r.registerIntegration(
        _integration('zoo', ['b', 'a']),
        enabled: true,
      );
      await r.registerIntegration(_integration('alpha', ['x']), enabled: true);
      await r.registerIntegration(_integration('off', ['y']));
      await r.registerIntegration(
        _integration('setup', ['z'], missingSteps: ['login']),
        enabled: true,
      );
      expect(_names(_cat(r).activeSpecs()), ['alpha__x', 'zoo__a', 'zoo__b']);
      r.setToolEnabled('zoo__a', enabled: false);
      expect(r.isToolEnabled('zoo__a'), isFalse);
      expect(_names(_cat(r).activeSpecs()), ['alpha__x', 'zoo__b']);
      expect(_cat(r).lookup('zoo__a'), isNull);
      expect(_cat(r).lookup('off__y'), isNull);
      expect(_cat(r).lookup('zoo__b')!.name, 'zoo__b');
      r.setToolEnabled('zoo__a', enabled: true);
      expect(_names(_cat(r).activeSpecs()), ['alpha__x', 'zoo__a', 'zoo__b']);
      expect(_cat(r).activeSpecs().first.description, 'Tool x von alpha');
    });

    test('Datenschutz: sensible Tools nur ab Mindeststufe', () async {
      final r = ToolRegistry(sensitiveMinimum: PrivacyLevel.tee);
      await r.registerIntegration(
        _integration('contacts', ['find'], sensitive: true),
        enabled: true,
      );
      await r.registerIntegration(
        _integration('weather', ['now']),
        enabled: true,
      );
      expect(_names(r.activeSpecsFor(PrivacyLevel.standard, sessionId: 's1')), [
        'weather__now',
      ]);
      expect(_names(r.activeSpecsFor(PrivacyLevel.eu, sessionId: 's1')), [
        'weather__now',
      ]);
      expect(_names(r.activeSpecsFor(PrivacyLevel.tee, sessionId: 's1')), [
        'contacts__find',
        'weather__now',
      ]);
      expect(_names(r.activeSpecsFor(PrivacyLevel.local, sessionId: 's1')), [
        'contacts__find',
        'weather__now',
      ]);
      final eu = r.catalogFor(PrivacyLevel.eu, sessionId: 's1');
      expect(_names(eu.activeSpecs()), ['weather__now']);
      expect(eu.lookup('contacts__find'), isNull);
      expect(
        r
            .catalogFor(PrivacyLevel.tee, sessionId: 's1')
            .lookup('contacts__find'),
        isNotNull,
      );

      r.sensitiveMinimum = null;
      expect(r.sensitiveMinimum, isNull);
      expect(eu.lookup('contacts__find'), isNotNull);
    });

    test('ohne Mindeststufe gehen sensible Tools überall hin', () async {
      final r = ToolRegistry();
      await r.registerIntegration(
        _integration('contacts', ['find'], sensitive: true),
        enabled: true,
      );
      expect(_names(r.activeSpecsFor(PrivacyLevel.standard, sessionId: 's1')), [
        'contacts__find',
      ]);
    });
  });

  group('Meta-Tool-Modus', () {
    Future<ToolRegistry> registryWith(int tools, {int threshold = 30}) async {
      final r = ToolRegistry(metaToolThreshold: threshold);
      await r.registerIntegration(
        _integration('cal', [
          for (var i = 0; i < tools ~/ 2; i++) 'event$i',
        ], displayName: 'Kalender'),
        enabled: true,
      );
      await r.registerIntegration(
        _integration('notes', [
          for (var i = 0; i < tools - tools ~/ 2; i++) 'note$i',
        ], displayName: 'Notizen'),
        enabled: true,
      );
      return r;
    }

    test('29 aktive Tools: alle direkt, kein Meta-Tool', () async {
      final r = await registryWith(29);
      expect(_cat(r).activeSpecs(), hasLength(29));
      expect(_cat(r).lookup(ToolSearchTool.toolName), isNull);
    });

    test('ab 30 aktiven Tools: nur tools__search mit Kategorien', () async {
      final r = await registryWith(30);
      final specs = _cat(r).activeSpecs();
      expect(_names(specs), [ToolSearchTool.toolName]);
      expect(specs.single.description, contains('cal (Kalender)'));
      expect(specs.single.description, contains('notes (Notizen)'));
      expect(
        (specs.single.inputSchema['properties']! as Map)['category'],
        containsPair('enum', ['cal', 'notes']),
      );
    });

    test('Suche schaltet Treffer für die Sitzung frei', () async {
      final r = await registryWith(30);
      final changes = <void>[];
      r.changes.listen(changes.add);
      final search = _cat(r).lookup(ToolSearchTool.toolName)!;
      final o = await search.execute({'query': 'note3'}, _ctx('s1'));
      final found = (jsonDecode(o.text) as Map)['tools'] as List;
      expect(found.map((t) => (t as Map)['name']), ['notes__note3']);
      expect(_names(_cat(r).activeSpecs()), [
        ToolSearchTool.toolName,
        'notes__note3',
      ]);
      expect(r.unlockedTools('s1'), {'notes__note3'});

      await search.execute({'query': 'event7'}, _ctx('s1'));
      expect(_names(_cat(r).activeSpecs()), [
        ToolSearchTool.toolName,
        'cal__event7',
        'notes__note3',
      ]);

      // Sessions are independent: s2 does not see s1's tools and vice versa.
      await search.execute({'query': 'event2'}, _ctx('s2'));
      expect(r.unlockedTools('s2'), {'cal__event2'});
      expect(r.unlockedTools('s1'), {'cal__event7', 'notes__note3'});
      expect(_names(_cat(r, session: 's2').activeSpecs()), [
        ToolSearchTool.toolName,
        'cal__event2',
      ]);
      r.endSession('s1');
      expect(_names(_cat(r).activeSpecs()), [ToolSearchTool.toolName]);
      expect(r.unlockedTools('s1'), isEmpty);
      expect(r.unlockedTools('s2'), {'cal__event2'});
      r.unregister('cal');
      expect(r.unlockedTools('s2'), isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(changes, isNotEmpty);
    });

    test('nicht freigeschaltete aktive Tools bleiben aufrufbar', () async {
      final r = await registryWith(30);
      expect(_cat(r).lookup('cal__event0'), isNotNull);
    });

    test('Meta-Modus zählt nach Datenschutzfilter', () async {
      final r = ToolRegistry(
        metaToolThreshold: 3,
        sensitiveMinimum: PrivacyLevel.tee,
      );
      await r.registerIntegration(
        _integration('contacts', ['a', 'b'], sensitive: true),
        enabled: true,
      );
      await r.registerIntegration(_integration('w', ['x']), enabled: true);
      expect(_names(r.activeSpecsFor(PrivacyLevel.standard, sessionId: 's1')), [
        'w__x',
      ]);
      expect(_names(r.activeSpecsFor(PrivacyLevel.tee, sessionId: 's1')), [
        ToolSearchTool.toolName,
      ]);
      final search = r
          .catalogFor(PrivacyLevel.tee, sessionId: 's1')
          .lookup(ToolSearchTool.toolName)!;
      final o = await search.execute({'category': 'contacts'}, _ctx('s'));
      expect(o.text, contains('contacts__a'));
      expect(
        r
            .catalogFor(PrivacyLevel.standard, sessionId: 's1')
            .lookup(ToolSearchTool.toolName),
        isNull,
      );
    });

    test('Executor führt tools__search über die Registry aus', () async {
      final r = await registryWith(30);
      final executor = ToolExecutor(catalog: _cat(r));
      final events = await executor.invokeAll(const [
        ToolCallBlock(
          id: '1',
          name: ToolSearchTool.toolName,
          argumentsJson: '{"query": "note1"}',
        ),
      ], _ctx('s1')).toList();
      final o = events.whereType<ToolFinished>().single.outcome;
      expect(o.isError, isFalse);
      expect(o.text, startsWith('<tool_data tool="tools__search">'));
      expect(r.unlockedTools('s1'), contains('notes__note1'));
    });
  });

  test('changes meldet Änderungen; dispose schließt', () async {
    final r = ToolRegistry();
    var count = 0;
    final sub = r.changes.listen((_) => count++);
    await r.registerIntegration(_integration('cal', ['a']));
    r
      ..setEnabled('cal', enabled: true)
      ..setToolEnabled('cal__a', enabled: false)
      ..reportError('cal', 'x')
      ..clearError('cal')
      ..unregister('cal');
    await Future<void>.delayed(Duration.zero);
    expect(count, greaterThanOrEqualTo(7));
    await sub.cancel();
    await r.dispose();
    r.endSession('s1'); // no error after dispose
  });
}
