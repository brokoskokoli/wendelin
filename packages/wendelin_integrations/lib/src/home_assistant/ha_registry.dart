import 'dart:async';
import 'dart:convert';

import 'ha_model.dart';

/// Joins states with rooms: name = `friendly_name`, room from [areas]
/// (entity id → area name). Sorted by room, then name.
List<HaEntity> haEntitiesFrom(List<HaState> states, Map<String, String> areas) {
  final list =
      [
        for (final s in states)
          HaEntity(
            entityId: s.entityId,
            name: s.friendlyName,
            area: areas[s.entityId],
            deviceClass: switch (s.attributes['device_class']) {
              final String c when c.isNotEmpty => c,
              _ => null,
            },
          ),
      ]..sort((a, b) {
        final byArea = (a.area ?? '~').toLowerCase().compareTo(
          (b.area ?? '~').toLowerCase(),
        );
        return byArea != 0
            ? byArea
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  return list;
}

/// Reads area, device and entity registry over an open WebSocket ([socket]
/// is a `dart:io` WebSocket or any `Stream` + `add` sink) and returns the
/// room name per entity id (entity's own area, else its device's). Throws
/// on protocol errors; a missing admin right yields an empty map.
Future<Map<String, String>> haFetchAreas(
  Stream<Object?> incoming,
  void Function(String) send,
  String token,
) async {
  final it = StreamIterator<Object?>(incoming);
  Future<Map<String, Object?>> next() async {
    if (!await it.moveNext()) throw StateError('closed');
    final raw = it.current;
    final json = jsonDecode(
      raw is String ? raw : utf8.decode(raw! as List<int>),
    );
    return json as Map<String, Object?>;
  }

  try {
    var msg = await next();
    if (msg['type'] != 'auth_required') throw StateError('auth');
    send(jsonEncode({'type': 'auth', 'access_token': token}));
    msg = await next();
    if (msg['type'] != 'auth_ok') throw StateError('auth');
    Future<List<Map<String, Object?>>?> list(int id, String type) async {
      send(jsonEncode({'id': id, 'type': type}));
      while (true) {
        final m = await next();
        if (m['id'] != id) continue;
        final result = m['result'];
        if (m['success'] != true || result is! List<Object?>) return null;
        return [
          for (final r in result)
            if (r is Map<String, Object?>) r,
        ];
      }
    }

    final areas = await list(1, 'config/area_registry/list');
    final devices = await list(2, 'config/device_registry/list');
    final entities = await list(3, 'config/entity_registry/list');
    if (areas == null || entities == null) return const {};
    final areaName = {
      for (final a in areas)
        if (a['area_id'] is String && a['name'] is String)
          a['area_id']! as String: a['name']! as String,
    };
    final deviceArea = {
      for (final d in devices ?? const <Map<String, Object?>>[])
        if (d['id'] is String && d['area_id'] is String)
          d['id']! as String: d['area_id']! as String,
    };
    final out = <String, String>{};
    for (final e in entities) {
      final id = e['entity_id'];
      if (id is! String) continue;
      final areaId = e['area_id'] ?? deviceArea[e['device_id']];
      final name = areaName[areaId];
      if (name != null) out[id] = name;
    }
    return out;
  } finally {
    await it.cancel();
  }
}
