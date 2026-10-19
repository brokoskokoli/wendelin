import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';
import 'bring_server.dart';

/// Kanarienwerte: Passwort und Tokens dürfen in keinem Ergebnis, Fehlertext,
/// `toString` oder Log auftauchen.
void main() {
  const password = 'KANARIE-passwort-4711';
  const email = 'kontrakt@example.org';

  test('Passwort und Tokens nirgends sichtbar', () async {
    final server = BringServer()..password = password;
    final log = <String>[];
    final reported = <String>[];
    final api = server.api(log: log.add);
    // Einmal anmelden: danach liegen nur die Tokens im Speicher.
    final secrets = FakeBringSecrets(session: await api.login(email, password));
    final bring = BringIntegration(
      api,
      secrets,
      onError: (m, _) => reported.add(m),
    );
    final seen = <String>[];
    final tokens = <String>{};

    void record(ToolOutcome o) {
      seen
        ..add(o.text)
        ..add(o.summary ?? '')
        ..add('$o');
      final s = secrets.session;
      if (s != null) {
        tokens
          ..add(s.accessToken)
          ..add(s.refreshToken!);
        seen.add('$s');
      }
    }

    Future<ToolOutcome> call(String name, Map<String, Object?> args) async {
      final t = bring.tools.singleWhere((t) => t.name == name);
      seen.add(t.describeForConfirmation(args));
      final o = await t.execute(args, ctx());
      record(o);
      return o;
    }

    // Erfolgreiche Aufrufe aller Tools samt Undo und Token-Erneuerung.
    record(await call('bring__list_lists', {}));
    final add = await call('bring__add_items', {
      'items': [
        {'name': 'Milch', 'spec': '2 Liter'},
        'Eier',
      ],
    });
    server.expireTokens();
    await call('bring__get_items', {});
    await add.undo!();
    final done = await call('bring__complete_item', {'item': 'Äpfel'});
    await done.undo!();
    final removed = await call('bring__remove_item', {'item': 'Milch'});
    await removed.undo!();

    // Fehlerpfade: 401 nach Erneuerung, 429, 5xx, HTML, falsches Passwort.
    for (final answer in [
      canned(503, bringFixture('maintenance.html')),
      canned(200, bringFixture('maintenance.html')),
    ]) {
      server.next.add(answer);
      await call('bring__list_lists', {});
    }
    server.rejectTokens = true;
    await call('bring__get_items', {});
    server.rejectTokens = false;
    // Refresh abgelehnt: „Bitte neu anmelden“, Sitzung verworfen.
    server
      ..expireTokens()
      ..revokeRefresh();
    await call('bring__list_lists', {});
    expect(secrets.session, isNull);
    seen.add((await bring.reconnect())?.message ?? '');
    // Zuletzt, weil danach eine Sperre gilt.
    secrets.session = await server.api().login(email, password);
    server.next.add(canned(429));
    await call('bring__list_lists', {});
    expect(log.last, 'Bring! lists → 429');

    seen
      ..addAll(log)
      ..addAll(reported);
    final all = seen.join('\n');
    expect(tokens, isNotEmpty);
    expect(reported, isNotEmpty);
    expect(all, isNot(contains(password)));
    for (final t in tokens) {
      expect(all, isNot(contains(t)));
    }
  });

  test('Ausnahmen der API enthalten keine Geheimnisse', () async {
    final server = BringServer()..password = password;
    final api = server.api();
    final auth = await api.login(email, password);
    final errors = <String>[];
    Future<void> catching(Future<Object?> f) async {
      try {
        await f;
      } on PortException catch (e) {
        errors
          ..add(e.message)
          ..add('$e');
      }
    }

    await catching(api.login(email, 'x$password'));
    server.expireTokens();
    await catching(api.lists(auth));
    server.revokeRefresh();
    await catching(api.refresh(auth));
    expect(errors, hasLength(6));
    final all = errors.join('\n');
    for (final secret in [password, auth.accessToken, auth.refreshToken!]) {
      expect(all, isNot(contains(secret)));
    }
    expect('$auth', 'BringAuth(<verborgen>)');
  });
}
