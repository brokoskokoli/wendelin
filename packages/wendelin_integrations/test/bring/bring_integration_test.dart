import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';
import 'bring_server.dart';

const _login = BringCredentials(
  email: 'kontrakt@example.org',
  password: 'kanarien-passwort',
);

void main() {
  group('BringIntegration', () {
    test('Metadaten, Tools und Risikostufen', () {
      final b = BringIntegration(FakeBringApi(), FakeBringSecrets());
      expect(b.id, 'bring');
      expect(b.displayName, 'Bring! Einkaufsliste');
      expect(b.iconId, isNotEmpty);
      expect(b.sensitive, isFalse);
      expect(b.platforms, {AppPlatform.android, AppPlatform.ios});
      expect(
        {for (final t in b.tools) t.name: t.risk},
        {
          'bring__list_lists': RiskLevel.read,
          'bring__get_items': RiskLevel.read,
          'bring__add_items': RiskLevel.write,
          'bring__remove_item': RiskLevel.write,
          'bring__complete_item': RiskLevel.write,
        },
      );
      for (final t in b.tools) {
        expect(t.name, matches(RegExp(r'^bring__[a-z_]+$')));
        expect(t.description, isNotEmpty);
        expect(t.inputSchema['type'], 'object');
      }
    });

    test('verfügbar ohne App; Login als Einrichtungsschritt', () async {
      final secrets = FakeBringSecrets();
      final b = BringIntegration(FakeBringApi(), secrets);
      expect(await b.checkAvailability(), Availability.yes);
      expect(b.setup.single.kind, SetupStepKind.login);
      expect(b.setup.single.optional, isFalse);
      expect((await b.setupState()).missingSteps, [BringIntegration.loginStep]);
      secrets.login = _login;
      expect((await b.setupState()).complete, isTrue);
    });

    test('Fallback-Text für das Teilen an die Bring!-App', () {
      expect(BringAppFallback.androidPackage, 'ch.publisheria.bring');
      expect(BringAppFallback.note, contains('nicht nötig'));
      expect(
        BringAppFallback.shareText(const [
          BringItem(name: 'Milch', spec: '2 Liter'),
          BringItem(name: 'Eier'),
        ]),
        'Milch (2 Liter)\nEier',
      );
    });
  });

  group('Sitzung', () {
    late FakeBringApi api;
    late FakeBringSecrets secrets;
    late List<String> errors;
    late int recovered;
    late BringIntegration bring;

    setUp(() {
      api = FakeBringApi();
      secrets = FakeBringSecrets(login: _login);
      errors = [];
      recovered = 0;
      bring = BringIntegration(
        api,
        secrets,
        onError: errors.add,
        onRecovered: () => recovered++,
      );
    });

    Future<ToolOutcome> lists() => bring.tools.first.execute({}, ctx());

    test('erste Nutzung meldet an und speichert die Sitzung', () async {
      expect((await lists()).isError, isFalse);
      expect(api.logins, 1);
      expect(secrets.session, isNotNull);
      await lists();
      expect(api.logins, 1);
    });

    test('gespeicherte Sitzung wird ohne Login genutzt', () async {
      final auth = await api.login(_login.email, _login.password);
      secrets.session = auth;
      final b = BringIntegration(api, secrets);
      await b.tools.first.execute({}, ctx());
      expect(api.logins, 1);
    });

    test('abgelaufenes Token: einmal erneuern, Aufruf wiederholen', () async {
      await lists();
      api.expireTokens();
      final o = await lists();
      expect(o.isError, isFalse);
      expect(api.refreshes, 1);
      expect(api.logins, 1);
      expect(secrets.session!.accessToken, 'fake-access-2');
      expect(errors, isEmpty);
    });

    test('Erneuerung abgelehnt: neu anmelden', () async {
      await lists();
      api
        ..expireTokens()
        ..revokeRefresh();
      expect((await lists()).isError, isFalse);
      expect(api.logins, 2);
    });

    test('Sitzung ohne Refresh-Token: neu anmelden', () async {
      secrets.session = const BringAuth(userUuid: 'u', accessToken: 'alt');
      expect((await lists()).isError, isFalse);
      expect(api.refreshes, 0);
      expect(api.logins, 1);
    });

    test('Login abgelehnt: Fehlerzustand, Sitzung verworfen', () async {
      secrets
        ..login = const BringCredentials(
          email: 'kontrakt@example.org',
          password: 'alt',
        )
        ..session = const BringAuth(userUuid: 'u', accessToken: 'alt');
      final o = await lists();
      expect(o.isError, isTrue);
      expect(o.text, contains('Passwort falsch'));
      expect(o.text, contains(bringFallbackHint));
      expect(errors.single, contains('Passwort falsch'));
      expect(secrets.session, isNull);
      expect(bring.session.failed, isTrue);
    });

    test('401 nach Erneuerung: Fehlerzustand', () async {
      await lists();
      api.rejectTokens = true;
      // Erster Aufruf 401, nach der Erneuerung wieder 401.
      final o = await lists();
      expect(o.isError, isTrue);
      expect(api.refreshes, 1);
      expect(errors, hasLength(1));
      expect(secrets.session, isNull);
    });

    test('nicht eingerichtet: kein Fehlerzustand', () async {
      secrets.login = null;
      final o = await lists();
      expect(o.isError, isTrue);
      expect(o.text, BringSession.notSetUp.message);
      expect(errors, isEmpty);
    });

    test('unbekannte Liste (404): kein Fehlerzustand', () async {
      await lists();
      api.failNext(
        'items',
        const PortException(
          PortErrorKind.notFound,
          'Bring!-Liste nicht gefunden',
        ),
      );
      final o = await bring.tools[1].execute({}, ctx());
      expect(o.text, 'Bring!-Liste nicht gefunden');
      expect(errors, isEmpty);
    });

    test('Fehlerzustand endet mit dem nächsten Erfolg (reconnect)', () async {
      api.failNext(
        'lists',
        const PortException(
          PortErrorKind.unavailable,
          'Bring! ist nicht erreichbar',
        ),
      );
      expect(await bring.reconnect(), contains('nicht erreichbar'));
      // Vorübergehend: kein Fehlerzustand.
      expect(errors, isEmpty);
      expect(bring.session.failed, isFalse);
      api.failNext(
        'lists',
        const PortException(
          PortErrorKind.failed,
          'Bring!: unerwartete Antwort',
        ),
      );
      expect(await bring.reconnect(), contains(bringFallbackHint));
      expect(errors, hasLength(1));
      expect(recovered, 0);
      expect(await bring.reconnect(), isNull);
      expect(recovered, 1);
      expect(bring.session.failed, isFalse);
      await lists();
      expect(recovered, 1);
    });

    test('signOut verwirft die Sitzung', () async {
      await lists();
      await bring.signOut();
      expect(secrets.session, isNull);
      await lists();
      expect(api.logins, 2);
    });

    test('parallele Aufrufe teilen eine Erneuerung', () async {
      await lists();
      api.expireTokens();
      final results = await Future.wait([lists(), lists(), lists()]);
      expect(results.every((o) => !o.isError), isTrue);
      expect(api.refreshes, 1);
    });

    test(
      'Fehler beim Lesen der Secrets laufen nicht als Absturz durch',
      () async {
        secrets.failNext(
          'auth',
          const PortException(
            PortErrorKind.failed,
            'Schlüsselspeicher gesperrt',
          ),
        );
        final o = await lists();
        expect(o.isError, isTrue);
        expect(o.text, contains('Schlüsselspeicher gesperrt'));
      },
    );
  });

  group('Fehlerzustand mit HttpBringApi gegen Fixtures', () {
    late BringServer server;
    late List<String> errors;
    late BringIntegration bring;
    late FakeBringSecrets secrets;

    setUp(() {
      server = BringServer();
      errors = [];
      secrets = FakeBringSecrets(login: _login);
      bring = BringIntegration(server.api(), secrets, onError: errors.add);
    });

    Future<ToolOutcome> call(String name, Map<String, Object?> args) =>
        bring.tools.singleWhere((t) => t.name == name).execute(args, ctx());

    test(
      'Ablauf: Login, Listen, Artikel, Schreiben, Token-Erneuerung',
      () async {
        final add = await call('bring__add_items', {
          'items': [
            {'name': 'Milch', 'spec': '2 Liter'},
            {'name': 'Eier'},
          ],
        });
        expect(add.isError, isFalse, reason: add.text);
        expect(server.openAtHome(), ['Milch', 'Äpfel', 'Eier']);
        server.expireTokens();
        final get = await call('bring__get_items', {});
        expect(get.isError, isFalse);
        expect(get.text, contains('"Eier"'));
        await add.undo!();
        expect(server.openAtHome(), ['Milch', 'Äpfel']);
        expect(errors, isEmpty);
      },
    );

    test('401 auch nach erfolgreicher Erneuerung → Fehler', () async {
      await call('bring__list_lists', {});
      server.rejectTokens = true;
      final before = server.requests.length;
      final o = await call('bring__get_items', {});
      expect(o.isError, isTrue);
      expect(o.text, contains('Sitzung abgelaufen'));
      expect(errors, hasLength(1));
      final paths = [
        for (final r in server.requests.skip(before))
          r.url.path.split('/').last,
      ];
      // lists 401 → token erneuert → lists erneut 401, dann Schluss.
      expect(paths, ['lists', 'token', 'lists']);
    });

    final lasting = <String, Canned Function()>{
      '401 nach Erneuerung': () =>
          canned(401, bringFixture('unauthorized.json')),
      'HTML-Antwort': () => canned(200, bringFixture('maintenance.html')),
      'fehlende Felder': () =>
          canned(200, bringFixture('items_missing_fields.json')),
      'unerwarteter Status 418': () => canned(418),
    };
    for (final MapEntry(key: name, value: answer) in lasting.entries) {
      test('$name → definierter Fehler, Integration auf „Fehler“', () async {
        // Anmelden und Listen auflösen, dann scheitert der Artikelabruf.
        await call('bring__list_lists', {});
        if (name.startsWith('401')) {
          server.next.addAll([answer(), answer(), answer()]);
        } else {
          server.next.add(answer());
        }
        server.next.insert(0, canned(200, bringFixture('lists.json')));
        final o = await call('bring__get_items', {});
        expect(o.isError, isTrue);
        expect(o.text, contains(bringFallbackHint));
        expect(o.text, isNot(contains('<html')));
        expect(errors, hasLength(1), reason: o.text);
      });
    }

    final temporary = <String, Canned Function()>{
      '429': () => canned(429, '', {'retry-after': '0'}),
      '500': () => canned(500, bringFixture('maintenance.html')),
      '503': () => canned(503),
    };
    for (final MapEntry(key: name, value: answer) in temporary.entries) {
      test(
        '$name → Fehler, aber nicht pausiert; Folgeaufruf gelingt',
        () async {
          await call('bring__list_lists', {});
          server.next.addAll([
            canned(200, bringFixture('lists.json')),
            answer(),
          ]);
          final o = await call('bring__get_items', {});
          expect(o.isError, isTrue);
          expect(o.text, contains(bringRetryHint));
          expect(o.text, isNot(contains(bringFallbackHint)));
          expect(o.text, isNot(contains('<html')));
          expect(errors, isEmpty);
          expect(bring.session.failed, isFalse);
          final again = await call('bring__get_items', {});
          expect(again.isError, isFalse, reason: again.text);
        },
      );
    }

    test(
      '429-Sperre bleibt: Aufrufe scheitern ohne Anfrage, ohne Pause',
      () async {
        final clock = FixedClock(DateTime.utc(2026, 10, 13, 12));
        bring = BringIntegration(
          HttpBringApi(client: server.client, clock: clock),
          secrets,
          onError: errors.add,
        );
        await call('bring__list_lists', {});
        server.next.add(canned(429, '', {'retry-after': '60'}));
        expect((await call('bring__list_lists', {})).isError, isTrue);
        final sent = server.requests.length;
        final blocked = await call('bring__get_items', {});
        expect(blocked.text, contains('Anfragelimit'));
        expect(server.requests, hasLength(sent));
        expect(errors, isEmpty);
        clock.advance(const Duration(seconds: 60));
        expect((await call('bring__get_items', {})).isError, isFalse);
      },
    );

    test('Refresh 503 → kein Login-Fallback, Fehler ohne Pause', () async {
      await call('bring__list_lists', {});
      server.expireTokens();
      final before = server.requests.length;
      // lists → 401 (abgelaufen), token → 503.
      server.next.addAll([
        canned(401, bringFixture('unauthorized.json')),
        canned(503),
      ]);
      final o = await call('bring__list_lists', {});
      expect(o.isError, isTrue);
      expect(o.text, contains('Serverfehler'));
      final paths = [
        for (final r in server.requests.skip(before))
          r.url.path.split('/').last,
      ];
      expect(paths, ['lists', 'token']);
      expect(paths, isNot(contains('bringauth')));
      expect(errors, isEmpty);
    });
  });
}
