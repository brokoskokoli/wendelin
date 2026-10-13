import '../src/bring/bring_api.dart';
import '../src/common/port_exception.dart';
import 'fake_failures.dart';

/// One list of [FakeBringApi].
final class FakeBringList {
  /// Creates a list with copies of [purchase] and [recently].
  FakeBringList(
    this.uuid,
    this.name, {
    List<BringItem> purchase = const [],
    List<BringItem> recently = const [],
  }) : purchase = [...purchase],
       recently = [...recently];

  /// `listUuid`.
  final String uuid;

  /// Display name.
  final String name;

  /// Open items (mutable).
  final List<BringItem> purchase;

  /// Recently bought items (mutable).
  final List<BringItem> recently;
}

/// In-memory Bring! account; passes `bringApiContract`.
///
/// Defaults match the contract state: lists „Zuhause“ (default, open
/// „Milch“ 1 Liter, „Äpfel“; recently „Brot“) and „Büro“ (open „Kaffee“).
/// Tokens are counted up (`fake-access-1`, …); [expireTokens] invalidates
/// all access tokens, [revokeRefresh] all refresh tokens. Failures can be
/// injected per method with [failNext] (`login`, `refresh`, `lists`,
/// `items`, `saveItem`, `removeItem`, `completeItem`).
final class FakeBringApi with FakeFailures implements BringApi {
  /// Creates the fake.
  FakeBringApi({
    this.email = 'kontrakt@example.org',
    this.password = 'kanarien-passwort',
    List<FakeBringList>? lists,
    this.defaultListUuid = 'list-zuhause',
  }) : accountLists = lists ?? defaultLists();

  /// The contract state.
  static List<FakeBringList> defaultLists() => [
    FakeBringList(
      'list-zuhause',
      'Zuhause',
      purchase: const [
        BringItem(name: 'Milch', spec: '1 Liter', uuid: 'item-1'),
        BringItem(name: 'Äpfel', uuid: 'item-2'),
      ],
      recently: const [BringItem(name: 'Brot', uuid: 'item-3')],
    ),
    FakeBringList(
      'list-buero',
      'Büro',
      purchase: const [BringItem(name: 'Kaffee', uuid: 'item-4')],
    ),
  ];

  /// Accepted e-mail.
  final String email;

  /// Accepted password.
  final String password;

  /// The lists (mutable).
  final List<FakeBringList> accountLists;

  /// Default list returned by [login].
  final String? defaultListUuid;

  /// User id of the account.
  static const userUuid = 'user-fake';

  final Set<String> _access = {};
  final Set<String> _refresh = {};
  var _n = 0;

  /// Number of successful logins and refreshes.
  int logins = 0, refreshes = 0;

  /// While `true`, every access token is rejected (`permissionDenied` even
  /// right after a refresh or login, like a revoked account).
  bool rejectTokens = false;

  /// Invalidates all access tokens (next call: `permissionDenied`).
  void expireTokens() => _access.clear();

  /// Invalidates all refresh tokens.
  void revokeRefresh() => _refresh.clear();

  /// The list [uuid], if any.
  FakeBringList? list(String uuid) {
    for (final l in accountLists) {
      if (l.uuid == uuid) return l;
    }
    return null;
  }

  BringAuth _issue() {
    _n++;
    final a = 'fake-access-$_n';
    final r = 'fake-refresh-$_n';
    _access.add(a);
    _refresh.add(r);
    return BringAuth(
      userUuid: userUuid,
      publicUuid: 'public-fake',
      accessToken: a,
      refreshToken: r,
      defaultListUuid: defaultListUuid,
    );
  }

  void _check(BringAuth auth) {
    if (rejectTokens || !_access.contains(auth.accessToken)) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        'Bring!-Sitzung abgelaufen oder Zugang abgelehnt (HTTP 401/403)',
      );
    }
  }

  FakeBringList _list(String uuid) =>
      list(uuid) ??
      (throw const PortException(
        PortErrorKind.notFound,
        'Bring!-Liste nicht gefunden',
      ));

  @override
  Future<BringAuth> login(String email, String password) async {
    enter('login');
    if (email != this.email || password != this.password) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        'Bring!-Anmeldung abgelehnt: E-Mail oder Passwort falsch',
      );
    }
    logins++;
    return _issue();
  }

  @override
  Future<BringAuth> refresh(BringAuth auth) async {
    enter('refresh');
    if (!_refresh.remove(auth.refreshToken)) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        'Bring!-Sitzung abgelaufen, Erneuerung abgelehnt',
      );
    }
    refreshes++;
    final fresh = _issue();
    return auth.withTokens(
      accessToken: fresh.accessToken,
      refreshToken: fresh.refreshToken,
    );
  }

  @override
  Future<List<BringList>> lists(BringAuth auth) async {
    enter('lists');
    _check(auth);
    return [
      for (final l in accountLists) BringList(uuid: l.uuid, name: l.name),
    ];
  }

  @override
  Future<BringItems> items(BringAuth auth, String listUuid) async {
    enter('items');
    _check(auth);
    final l = _list(listUuid);
    return BringItems(purchase: l.purchase, recently: l.recently);
  }

  int _indexOf(List<BringItem> items, BringItem item) =>
      items.indexWhere((i) => i.name == item.name);

  @override
  Future<void> saveItem(BringAuth auth, String listUuid, BringItem item) async {
    enter('saveItem');
    _check(auth);
    final l = _list(listUuid);
    final r = _indexOf(l.recently, item);
    final uuid = r >= 0 ? l.recently.removeAt(r).uuid : item.uuid;
    final saved = BringItem(
      name: item.name,
      spec: item.spec,
      uuid: uuid ?? 'item-new-${++_n}',
    );
    final p = _indexOf(l.purchase, item);
    p >= 0 ? l.purchase[p] = saved : l.purchase.add(saved);
  }

  @override
  Future<void> removeItem(
    BringAuth auth,
    String listUuid,
    BringItem item,
  ) async {
    enter('removeItem');
    _check(auth);
    final l = _list(listUuid);
    l.purchase.removeWhere((i) => i.name == item.name);
    l.recently.removeWhere((i) => i.name == item.name);
  }

  @override
  Future<void> completeItem(
    BringAuth auth,
    String listUuid,
    BringItem item,
  ) async {
    enter('completeItem');
    _check(auth);
    final l = _list(listUuid);
    final p = _indexOf(l.purchase, item);
    if (p < 0) return;
    final old = l.purchase.removeAt(p);
    l.recently
      ..removeWhere((i) => i.name == item.name)
      ..insert(0, BringItem(name: old.name, spec: item.spec, uuid: old.uuid));
  }
}

/// In-memory [BringSecrets].
final class FakeBringSecrets with FakeFailures implements BringSecrets {
  /// Creates the store, optionally with [login] and [session].
  FakeBringSecrets({this.login, this.session});

  /// Stored credentials (as the app's setup would write them).
  BringCredentials? login;

  /// The cached session.
  BringAuth? session;

  @override
  Future<BringCredentials?> credentials() async {
    enter('credentials');
    return login;
  }

  @override
  Future<BringAuth?> auth() async {
    enter('auth');
    return session;
  }

  @override
  Future<void> saveAuth(BringAuth? auth) async {
    enter('saveAuth');
    session = auth;
  }
}
