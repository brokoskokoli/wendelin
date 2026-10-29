// Gerätetest WP107 (Bring! nur Tokens): Fake-Bring!-Server im Testprozess
// (MockClient), echter Secret-Store-Adapter im Speicher, echte UI.
// Szenarien WP107.1, .3, .5, .6, .7 (Sprachen über E2E_LANG).
// Läuft über `tool/e2e_android.sh integration_test/bring_tokens_e2e_test.dart`.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/di/bring.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/ui/routes.dart';
import 'package:wendelin/ui/screens/main_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'support/e2e.dart';

const _user = '00000000-0000-4000-8000-000000000001';
const _list = '00000000-0000-4000-8000-0000000000a1';

/// Minimal Bring! server: login, refresh, lists.
final class FakeBring {
  final requests = <String>[];
  final access = <String>{};
  final refresh = <String>{};
  var _n = 0;
  String email = 'wp107@example.org', password = 'geheim-wp107';

  int count(String p) => requests.where((r) => r.endsWith(p)).length;

  Map<String, Object?> _issue(bool login) {
    _n++;
    access.add('a$_n');
    refresh.add('r$_n');
    return {
      if (login) ...{
        'uuid': _user,
        'publicUuid': 'pub',
        'bringListUUID': _list,
      },
      'access_token': 'a$_n',
      'refresh_token': 'r$_n',
      'token_type': 'Bearer',
      'expires_in': 604799,
    };
  }

  http.Response _j(int s, Object body) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    s,
    headers: {'content-type': 'application/json; charset=UTF-8'},
  );

  http.Response get _no => _j(401, {'error': 'Unauthorized', 'errorcode': 401});

  Future<http.Response> handle(http.Request r) async {
    final p = r.url.path;
    requests.add('${r.method} $p');
    if (r.method == 'POST' && p.endsWith('/bringauth')) {
      final f = r.bodyFields;
      if (f['email'] != email || f['password'] != password) return _no;
      return _j(200, _issue(true));
    }
    if (r.method == 'POST' && p.endsWith('/bringauth/token')) {
      if (!refresh.remove(r.bodyFields['refresh_token'])) return _no;
      return _j(200, _issue(false));
    }
    final auth = r.headers['Authorization'] ?? '';
    if (!auth.startsWith('Bearer ') || !access.contains(auth.substring(7))) {
      return _no;
    }
    if (r.method == 'GET' && p.endsWith('/lists')) {
      return _j(200, {
        'lists': [
          {'listUuid': _list, 'name': 'Zuhause', 'theme': 'x'},
        ],
      });
    }
    return _j(404, {'error': 'Not Found'});
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Bring! nur Tokens: Login, Neustart, Refresh abgelehnt, '
      'Erneut verbinden, Abmelden', (tester) async {
    final server = FakeBring();
    final app = E2eApp(
      startup: const StartupSettings(
        setupWizardDone: true,
        enabledIntegrations: {'bring'},
      ),
      extraOverrides: [
        bringApiProvider.overrideWith(
          (ref) => HttpBringApi(client: MockClient(server.handle)),
        ),
      ],
    );

    Future<ProviderContainer> start() async {
      final c = await app.pump(tester);
      await pumpUntil(tester, find.byType(MainScreen));
      await tester.runAsync(() => c.read(toolRegistryReadyProvider.future));
      return c;
    }

    Future<void> openBring() async {
      Navigator.of(tester.element(find.byType(MainScreen)))
          .pushNamed(AppRoutes.bring);
      await pumpFor(tester, const Duration(seconds: 2));
    }

    Future<void> signIn(String pw) async {
      final l = l10n(tester);
      await tester.enterText(
        find
            .descendant(
              of: find.byKey(const ValueKey('bringEmail')),
              matching: find.byType(EditableText),
            )
            .first,
        server.email,
      );
      await tester.enterText(
        find
            .descendant(
              of: find.byKey(const ValueKey('bringPassword')),
              matching: find.byType(EditableText),
            )
            .first,
        pw,
      );
      await tester.tap(find.text(l.mcpLabelsSignIn));
      await pumpFor(tester, const Duration(seconds: 2));
    }

    Future<Map<String, String>> secretsDump(ProviderContainer c) async {
      final s = c.read(secretStoreProvider);
      final keys = <String>[];
      for (final k in ['bring.session', 'bring.email', 'bring.password']) {
        if (await s.read(k) != null) keys.add(k);
      }
      return {for (final k in keys) k: 'da'};
    }

    var c = await start();
    await openBring();
    final l = l10n(tester);
    expect(find.text(l.bringConnected), findsNothing);

    // WP107.1 Login
    await signIn(server.password);
    expect(find.text(l.bringConnected), findsOneWidget, reason: 'Verbunden');
    expect(find.text(l.ruleEditorActive), findsOneWidget, reason: 'Aktiv');
    expect(find.text(server.email), findsNothing, reason: 'keine E-Mail');
    expect(find.byType(EditableText), findsNothing, reason: 'Felder weg');
    final dump = await tester.runAsync(() => secretsDump(c));
    // ignore: avoid_print
    print('WP107.1 secrets=$dump requests=${server.requests}');
    expect(dump!.keys, ['bring.session']);
    expect(server.count('/bringauth'), 1);

    // WP107.3 Neustart: neuer Container, gleicher Secret-Store.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    c = await start();
    await openBring();
    expect(find.text(l.bringConnected), findsOneWidget);
    expect(find.text(l.ruleEditorActive), findsOneWidget);
    final info = c
        .read(toolRegistryProvider)
        .integrations
        .firstWhere((i) => i.id == 'bring');
    // ignore: avoid_print
    print(
      'WP107.3 status=${info.status} login-requests=${server.count('/bringauth')}',
    );
    expect(info.status, IntegrationStatus.active);
    expect(server.count('/bringauth'), 1, reason: 'kein neuer Login');

    // WP107.5 Refresh abgelehnt
    server.access.clear();
    server.refresh.clear();
    final logins = server.count('/bringauth');
    final bring = bringIntegrationOf(c.read(integrationsProvider))!;
    Object? thrown;
    await tester.runAsync(() async {
      try {
        await bring.session.lists();
      } on Object catch (e) {
        thrown = e;
      }
    });
    // ignore: avoid_print
    print('WP107.5 thrown=$thrown requests=${server.requests.skip(2)}');
    expect(thrown, isNotNull);
    expect(thrown.toString(), contains('abgelaufen'));
    expect(server.count('/bringauth'), logins, reason: 'kein Login-Versuch');
    expect(server.count('/bringauth/token'), 1);
    final failed = c
        .read(toolRegistryProvider)
        .integrations
        .firstWhere((i) => i.id == 'bring');
    // ignore: avoid_print
    print('WP107.5 status=${failed.status} error=${failed.error}');
    expect(failed.status, IntegrationStatus.error);

    // WP107.6 Erneut verbinden
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    c = await start();
    await openBring();
    final dump6 = await tester.runAsync(() => secretsDump(c));
    // ignore: avoid_print
    print('WP107.6 secrets nach Reauth=$dump6');
    if (find.text(l.bringReconnect).evaluate().isNotEmpty) {
      await tester.tap(find.text(l.bringReconnect));
      await pumpFor(tester);
    }
    expect(find.text(l.mcpLabelsSignIn), findsOneWidget, reason: 'Formular');
    await signIn(server.password);
    expect(find.text(l.bringConnected), findsOneWidget);
    expect(find.text(l.ruleEditorActive), findsOneWidget);
    expect(find.text(l.bringApiError), findsNothing);
    expect(server.count('/bringauth'), logins + 1);

    // WP107.7 Abmelden
    await tester.tap(find.text(l.mcpDetailSignOut));
    await pumpFor(tester);
    expect(find.text(l.bringSignOutBody), findsOneWidget);
    await tester.tap(find.text(l.mcpDetailSignOut).last);
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.text(l.mcpLabelsSignIn), findsOneWidget);
    final dump7 = await tester.runAsync(() => secretsDump(c));
    // ignore: avoid_print
    print('WP107.7 secrets=$dump7');
    expect(dump7, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
