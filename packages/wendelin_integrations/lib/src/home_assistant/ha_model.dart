import 'package:meta/meta.dart';

/// Address and long-lived access token of a Home Assistant instance. The
/// token is a secret: [toString] hides it, [url] is normalized by
/// `HaUrl.parse` (no trailing slash).
@immutable
final class HaEndpoint {
  /// Creates an endpoint.
  const HaEndpoint({required this.url, required this.token});

  /// Base URL, e.g. `http://192.168.1.20:8123`.
  final String url;

  /// Long-lived access token.
  final String token;

  @override
  bool operator ==(Object other) =>
      other is HaEndpoint && other.url == url && other.token == token;

  @override
  int get hashCode => Object.hash(url, token);

  @override
  String toString() => 'HaEndpoint($url, <verborgen>)';
}

/// State of one Home Assistant entity (`GET /api/states`).
@immutable
final class HaState {
  /// Creates a state.
  const HaState({
    required this.entityId,
    required this.state,
    this.attributes = const {},
  });

  /// Reads one element of the REST answer; `null` if it is malformed.
  static HaState? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['entity_id'];
    final state = json['state'];
    if (id is! String || !id.contains('.') || state is! String) return null;
    final attrs = json['attributes'];
    return HaState(
      entityId: id,
      state: state,
      attributes: attrs is Map<String, Object?> ? attrs : const {},
    );
  }

  /// `light.kitchen`.
  final String entityId;

  /// `on`, `off`, `unavailable`, `21.5`, …
  final String state;

  /// Attributes as sent by Home Assistant.
  final Map<String, Object?> attributes;

  /// Domain part of [entityId] (`light`).
  String get domain => haDomainOf(entityId);

  /// `friendly_name`, else [entityId].
  String get friendlyName => switch (attributes['friendly_name']) {
    final String s when s.trim().isNotEmpty => s.trim(),
    _ => entityId,
  };

  /// `unavailable` / `unknown`: nothing to restore, nothing to control.
  bool get isUnavailable => state == 'unavailable' || state == 'unknown';

  @override
  String toString() => 'HaState($entityId: $state)';
}

/// Domain of an entity id (`light.kitchen` → `light`).
String haDomainOf(String entityId) {
  final dot = entityId.indexOf('.');
  return dot < 0 ? entityId : entityId.substring(0, dot);
}

/// An entity with the name and room the user sees. [HaApi.entities] lists
/// all of them; the ones the user approved are kept in `HaEntityStore` and
/// are the only ones the model learns about.
@immutable
final class HaEntity {
  /// Creates an entity.
  const HaEntity({
    required this.entityId,
    required this.name,
    this.area,
    this.alwaysConfirm = false,
    this.missing = false,
  });

  /// Reads [toJson] output; `null` if malformed.
  static HaEntity? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['id'];
    final name = json['name'];
    final area = json['area'];
    if (id is! String || !id.contains('.') || name is! String) return null;
    return HaEntity(
      entityId: id,
      name: name,
      area: area is String && area.isNotEmpty ? area : null,
      alwaysConfirm: json['confirm'] == true,
      missing: json['missing'] == true,
    );
  }

  /// `light.kitchen`.
  final String entityId;

  /// Display name (`friendly_name`).
  final String name;

  /// Room (Home Assistant area), if assigned.
  final String? area;

  /// The user wants a confirmation for every call of this entity (K57:
  /// switches that power something critical). Such calls go through
  /// `ha__call_secure`.
  final bool alwaysConfirm;

  /// Home Assistant no longer lists the entity (WP135 A, set by the sync).
  /// Such an entity is not offered to the model and not resolved; the user
  /// removes it in the settings.
  final bool missing;

  /// Domain part of [entityId].
  String get domain => haDomainOf(entityId);

  /// Copy with a different [alwaysConfirm].
  HaEntity withConfirm(bool value) => HaEntity(
    entityId: entityId,
    name: name,
    area: area,
    alwaysConfirm: value,
    missing: missing,
  );

  /// Copy with the name, room and presence from Home Assistant.
  HaEntity synced({String? name, String? area, bool missing = false}) =>
      HaEntity(
        entityId: entityId,
        name: name ?? this.name,
        area: area,
        alwaysConfirm: alwaysConfirm,
        missing: missing,
      );

  /// JSON for the entity store.
  Map<String, Object?> toJson() => {
    'id': entityId,
    'name': name,
    if (area != null) 'area': area,
    if (alwaysConfirm) 'confirm': true,
    if (missing) 'missing': true,
  };

  @override
  bool operator ==(Object other) =>
      other is HaEntity &&
      other.entityId == entityId &&
      other.name == name &&
      other.area == area &&
      other.alwaysConfirm == alwaysConfirm &&
      other.missing == missing;

  @override
  int get hashCode => Object.hash(entityId, name, area, alwaysConfirm, missing);

  @override
  String toString() =>
      'HaEntity($entityId, $name, $area${alwaysConfirm ? ', confirm' : ''}'
      '${missing ? ', missing' : ''})';
}

/// A Home Assistant instance found in the local network.
@immutable
final class HaServer {
  /// Creates a server entry.
  const HaServer({required this.name, required this.url});

  /// Instance name (location name or host).
  final String name;

  /// Address to use as [HaEndpoint.url].
  final String url;

  @override
  bool operator ==(Object other) =>
      other is HaServer && other.name == name && other.url == url;

  @override
  int get hashCode => Object.hash(name, url);

  @override
  String toString() => 'HaServer($name, $url)';
}

/// One service call of Home Assistant (`POST /api/services/<domain>/<service>`).
typedef HaCall = ({String domain, String service, Map<String, Object?> data});
