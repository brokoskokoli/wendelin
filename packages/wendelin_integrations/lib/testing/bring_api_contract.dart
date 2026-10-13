import 'dart:async';

import 'package:test/test.dart';

import '../src/bring/bring_api.dart';
import '../src/common/port_exception.dart';

/// E-mail the account under test accepts.
const bringContractEmail = 'kontrakt@example.org';

/// Password the account under test accepts; must never show up in errors.
const bringContractPassword = 'kanarien-passwort';

/// What [bringApiContract] works on: a fresh account in the contract state
/// (lists „Zuhause“ = default with open „Milch“ (spec „1 Liter“) and
/// „Äpfel“ and recently „Brot“; „Büro“ with open „Kaffee“) plus a hook
/// that invalidates every issued access token.
typedef BringApiSetup = ({BringApi api, void Function() expireTokens});

/// Creates a fresh [BringApiSetup] per test.
typedef BringApiFactory = FutureOr<BringApiSetup> Function();

Matcher _portError(PortErrorKind kind) => throwsA(
  isA<PortException>()
      .having((e) => e.kind, 'kind', kind)
      .having(
        (e) => '${e.message} $e',
        'Text',
        allOf(
          isNot(contains(bringContractPassword)),
          isNot(contains('access')),
          isNot(contains('refresh-')),
        ),
      ),
);

/// Contract every [BringApi] must pass (fake and HTTP client against a
/// recorded/rebuilt backend).
void bringApiContract(BringApiFactory create, {required String name}) {
  group('BringApi-Vertrag: $name', () {
    late BringApi api;
    late void Function() expire;
    late BringAuth auth;

    setUp(() async {
      final s = await create();
      api = s.api;
      expire = s.expireTokens;
      auth = await api.login(bringContractEmail, bringContractPassword);
    });

    Future<BringList> listNamed(String n) async =>
        (await api.lists(auth)).singleWhere((l) => l.name == n);

    Future<BringItems> itemsOf(String n) async =>
        api.items(auth, (await listNamed(n)).uuid);

    BringItem? find(List<BringItem> items, String n) {
      for (final i in items) {
        if (i.name == n) return i;
      }
      return null;
    }

    test(
      'Login liefert Sitzung mit Standardliste, toString ohne Token',
      () async {
        expect(auth.userUuid, isNotEmpty);
        expect(auth.accessToken, isNotEmpty);
        expect(auth.defaultListUuid, (await listNamed('Zuhause')).uuid);
        expect('$auth', isNot(contains(auth.accessToken)));
        expect(BringAuth.fromJson(auth.toJson()), auth);
      },
    );

    test('falsches Passwort: permissionDenied ohne Passwort im Text', () {
      expect(
        api.login(bringContractEmail, 'falsch-$bringContractPassword'),
        _portError(PortErrorKind.permissionDenied),
      );
    });

    test('Listen', () async {
      final names = (await api.lists(auth)).map((l) => l.name);
      expect(names, containsAll(['Zuhause', 'Büro']));
    });

    test('Artikel: offen mit Mengenangabe und zuletzt gekauft', () async {
      final items = await itemsOf('Zuhause');
      expect(find(items.purchase, 'Milch')?.spec, '1 Liter');
      expect(find(items.purchase, 'Äpfel')?.spec, '');
      expect(find(items.recently, 'Brot'), isNotNull);
      expect(find((await itemsOf('Büro')).purchase, 'Kaffee'), isNotNull);
    });

    test('unbekannte Liste: notFound', () {
      expect(
        api.items(auth, 'gibt-es-nicht'),
        _portError(PortErrorKind.notFound),
      );
    });

    test('saveItem legt mit Mengenangabe an', () async {
      final l = await listNamed('Zuhause');
      await api.saveItem(
        auth,
        l.uuid,
        const BringItem(name: 'Eier', spec: '10'),
      );
      final items = await api.items(auth, l.uuid);
      expect(find(items.purchase, 'Eier')?.spec, '10');
    });

    test('saveItem holt zuletzt Gekauftes zurück und ändert Angaben', () async {
      final l = await listNamed('Zuhause');
      await api.saveItem(auth, l.uuid, const BringItem(name: 'Brot'));
      await api.saveItem(
        auth,
        l.uuid,
        const BringItem(name: 'Milch', spec: '2 Liter'),
      );
      final items = await api.items(auth, l.uuid);
      expect(find(items.purchase, 'Brot'), isNotNull);
      expect(find(items.recently, 'Brot'), isNull);
      expect(items.purchase.where((i) => i.name == 'Milch'), hasLength(1));
      expect(find(items.purchase, 'Milch')?.spec, '2 Liter');
    });

    test('completeItem verschiebt nach „zuletzt gekauft“', () async {
      final l = await listNamed('Zuhause');
      final milch = find((await api.items(auth, l.uuid)).purchase, 'Milch')!;
      await api.completeItem(auth, l.uuid, milch);
      final items = await api.items(auth, l.uuid);
      expect(find(items.purchase, 'Milch'), isNull);
      expect(find(items.recently, 'Milch'), isNotNull);
    });

    test('removeItem löscht offene und zuletzt gekaufte', () async {
      final l = await listNamed('Zuhause');
      await api.removeItem(auth, l.uuid, const BringItem(name: 'Äpfel'));
      await api.removeItem(auth, l.uuid, const BringItem(name: 'Brot'));
      final items = await api.items(auth, l.uuid);
      expect(find(items.purchase, 'Äpfel'), isNull);
      expect(find(items.recently, 'Brot'), isNull);
      expect(find(items.purchase, 'Milch'), isNotNull);
    });

    test('abgelaufenes Token: permissionDenied, refresh hilft', () async {
      expire();
      await expectLater(
        api.lists(auth),
        _portError(PortErrorKind.permissionDenied),
      );
      final fresh = await api.refresh(auth);
      expect(fresh.userUuid, auth.userUuid);
      expect(fresh.accessToken, isNot(auth.accessToken));
      expect(fresh.refreshToken, isNotNull);
      expect(await api.lists(fresh), isNotEmpty);
    });

    test('ungültiges oder fehlendes Refresh-Token: permissionDenied', () async {
      await expectLater(
        api.refresh(
          auth.withTokens(
            accessToken: auth.accessToken,
            refreshToken: 'ungueltig',
          ),
        ),
        _portError(PortErrorKind.permissionDenied),
      );
      await expectLater(
        api.refresh(
          BringAuth(userUuid: auth.userUuid, accessToken: auth.accessToken),
        ),
        _portError(PortErrorKind.permissionDenied),
      );
    });
  });
}
