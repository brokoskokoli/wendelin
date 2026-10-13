import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// Client of the unofficial Bring! REST API (see the README for endpoints,
/// source and terms-of-use note). Stateless: the caller keeps the
/// [BringAuth] and renews it (`BringSession`).
///
/// Every method throws `PortException` only, never a parse or socket error:
/// - `permissionDenied`: credentials or token rejected (HTTP 401/403),
/// - `notFound`: unknown list (HTTP 404),
/// - `unavailable`: unreachable, timeout, rate limit (429), server error
///   (5xx),
/// - `failed`: unexpected answer (HTML instead of JSON, missing fields,
///   other types, other status codes).
///
/// Messages are German, short and never contain the password, tokens or
/// the response body. Must pass `bringApiContract`.
abstract interface class BringApi {
  /// Signs in with e-mail and password.
  Future<BringAuth> login(String email, String password);

  /// A new access token from [auth]'s refresh token; keeps the old refresh
  /// token if the service does not send a new one.
  Future<BringAuth> refresh(BringAuth auth);

  /// The lists of the account.
  Future<List<BringList>> lists(BringAuth auth);

  /// Open („purchase“) and recently bought („recently“) items of a list.
  Future<BringItems> items(BringAuth auth, String listUuid);

  /// Puts [item] on the open list (with its [BringItem.spec]); an item in
  /// „recently“ moves back to open, an open one gets the new spec.
  Future<void> saveItem(BringAuth auth, String listUuid, BringItem item);

  /// Deletes [item] from the list (open or recently).
  Future<void> removeItem(BringAuth auth, String listUuid, BringItem item);

  /// Moves [item] from open to „recently“ (bought).
  Future<void> completeItem(BringAuth auth, String listUuid, BringItem item);
}

/// Session of a Bring! account. Tokens are secrets: [toString] hides them,
/// [toJson] is only for the `SecretStore`.
@immutable
final class BringAuth {
  /// Creates a session.
  const BringAuth({
    required this.userUuid,
    required this.accessToken,
    this.refreshToken,
    this.publicUuid,
    this.defaultListUuid,
  });

  /// Reads [toJson] output; `null` if fields are missing or of the wrong
  /// type.
  static BringAuth? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final user = json['userUuid'];
    final access = json['accessToken'];
    if (user is! String || access is! String) return null;
    String? opt(String key) => switch (json[key]) {
      final String s => s,
      _ => null,
    };
    return BringAuth(
      userUuid: user,
      accessToken: access,
      refreshToken: opt('refreshToken'),
      publicUuid: opt('publicUuid'),
      defaultListUuid: opt('defaultListUuid'),
    );
  }

  /// Account id (`uuid`).
  final String userUuid;

  /// Public account id (`publicUuid`), if known.
  final String? publicUuid;

  /// Bearer token.
  final String accessToken;

  /// Token for [BringApi.refresh], if any.
  final String? refreshToken;

  /// The account's default list (`bringListUUID`), if known.
  final String? defaultListUuid;

  /// Copy with new tokens.
  BringAuth withTokens({required String accessToken, String? refreshToken}) =>
      BringAuth(
        userUuid: userUuid,
        publicUuid: publicUuid,
        accessToken: accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        defaultListUuid: defaultListUuid,
      );

  /// JSON for the `SecretStore` (contains the tokens).
  Map<String, Object?> toJson() => {
    'userUuid': userUuid,
    'accessToken': accessToken,
    if (refreshToken != null) 'refreshToken': refreshToken,
    if (publicUuid != null) 'publicUuid': publicUuid,
    if (defaultListUuid != null) 'defaultListUuid': defaultListUuid,
  };

  @override
  bool operator ==(Object other) =>
      other is BringAuth &&
      other.userUuid == userUuid &&
      other.publicUuid == publicUuid &&
      other.accessToken == accessToken &&
      other.refreshToken == refreshToken &&
      other.defaultListUuid == defaultListUuid;

  @override
  int get hashCode => Object.hash(
    userUuid,
    publicUuid,
    accessToken,
    refreshToken,
    defaultListUuid,
  );

  @override
  String toString() => 'BringAuth(<verborgen>)';
}

/// E-mail and password of the Bring! account (secret: [toString] hides the
/// password).
@immutable
final class BringCredentials {
  /// Creates credentials.
  const BringCredentials({required this.email, required this.password});

  /// Login e-mail.
  final String email;

  /// Password.
  final String password;

  @override
  bool operator ==(Object other) =>
      other is BringCredentials &&
      other.email == email &&
      other.password == password;

  @override
  int get hashCode => Object.hash(email, password);

  @override
  String toString() => 'BringCredentials(<verborgen>)';
}

/// Where the Bring! secrets live (app: `SecretStore`). Never SQLite,
/// settings JSON, logs or exports.
abstract interface class BringSecrets {
  /// The stored login, or `null` if Bring! is not set up.
  Future<BringCredentials?> credentials();

  /// The cached session, or `null`.
  Future<BringAuth?> auth();

  /// Replaces the cached session; `null` deletes it.
  Future<void> saveAuth(BringAuth? auth);
}

/// A Bring! list.
@immutable
final class BringList {
  /// Creates a list.
  const BringList({required this.uuid, required this.name});

  /// `listUuid`.
  final String uuid;

  /// Display name, e.g. „Zuhause“.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is BringList && other.uuid == uuid && other.name == name;

  @override
  int get hashCode => Object.hash(uuid, name);

  @override
  String toString() => 'BringList($name)';
}

/// An item on a Bring! list.
@immutable
final class BringItem {
  /// Creates an item; [spec] is the quantity text, e.g. „2 Liter“.
  const BringItem({required this.name, this.spec = '', this.uuid});

  /// `itemId`: catalog name or free text, e.g. „Milch“.
  final String name;

  /// `specification`; empty if none.
  final String spec;

  /// Item instance id, if the service sent one.
  final String? uuid;

  /// JSON for the model (without the internal uuid).
  Map<String, Object?> toJson() => {
    'name': name,
    if (spec.isNotEmpty) 'spec': spec,
  };

  @override
  bool operator ==(Object other) =>
      other is BringItem &&
      other.name == name &&
      other.spec == spec &&
      other.uuid == uuid;

  @override
  int get hashCode => Object.hash(name, spec, uuid);

  @override
  String toString() => 'BringItem($name${spec.isEmpty ? '' : ', $spec'})';
}

/// Content of a Bring! list.
@immutable
final class BringItems {
  /// Creates the content; the lists are copied unmodifiable.
  BringItems({
    required List<BringItem> purchase,
    required List<BringItem> recently,
  }) : purchase = List.unmodifiable(purchase),
       recently = List.unmodifiable(recently);

  /// Open items.
  final List<BringItem> purchase;

  /// Recently bought items.
  final List<BringItem> recently;

  @override
  bool operator ==(Object other) =>
      other is BringItems &&
      const ListEquality<BringItem>().equals(other.purchase, purchase) &&
      const ListEquality<BringItem>().equals(other.recently, recently);

  @override
  int get hashCode => Object.hash(
    const ListEquality<BringItem>().hash(purchase),
    const ListEquality<BringItem>().hash(recently),
  );

  @override
  String toString() =>
      'BringItems(${purchase.length} offen, ${recently.length} zuletzt)';
}
