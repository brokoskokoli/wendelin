import 'ha_model.dart';
import 'ha_ports.dart';

/// How often the approved entities are compared with Home Assistant at most
/// when nobody asks for it (app start, prompt).
const haSyncInterval = Duration(days: 1);

/// After a failed comparison the next one waits at least this long.
const haSyncRetry = Duration(minutes: 15);

/// The approved entities after a comparison with [fresh], the list Home
/// Assistant reports now (WP135 A).
///
/// - Name and room come from Home Assistant. Without a single room in
///   [fresh] (no admin rights, registry not readable) the saved rooms stay.
/// - An entity [fresh] does not list gets `missing`; it is kept (the user
///   removes it) but no longer goes to the model or to `resolve`. One that
///   returns loses the mark.
/// - An entity of [fresh] that is not approved is never added (K10).
/// - An empty [fresh] is no evidence (a flaky answer, not "everything is
///   gone"): returns `null`, nothing changes.
List<HaEntity>? haReconcile(List<HaEntity> approved, List<HaEntity> fresh) {
  if (fresh.isEmpty) return null;
  final byId = {for (final f in fresh) f.entityId: f};
  final roomsKnown = fresh.any((f) => f.area != null);
  return [
    for (final e in approved)
      switch (byId[e.entityId]) {
        final f? => e.synced(
          name: f.name,
          area: roomsKnown ? f.area : e.area,
          deviceClass: f.deviceClass ?? e.deviceClass,
        ),
        null => e.synced(
          area: e.area,
          deviceClass: e.deviceClass,
          missing: true,
        ),
      },
  ];
}

/// Compares the stored approved entities with [fresh] and saves the result
/// if it differs; remembers [now] as the time of the comparison. Reads the
/// store only now (after the network call), so a change the user made in
/// the meantime is not overwritten. Returns the stored list afterwards.
Future<List<HaEntity>> haSyncStore(
  HaEntityStore store,
  List<HaEntity> fresh,
  DateTime now,
) async {
  final approved = await store.load();
  final next = haReconcile(approved, fresh);
  if (next == null) return approved;
  if (!_same(approved, next)) await store.save(next);
  await store.saveLastSync(now);
  return next;
}

bool _same(List<HaEntity> a, List<HaEntity> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
