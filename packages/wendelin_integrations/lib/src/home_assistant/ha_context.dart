import 'package:wendelin_core/wendelin_core.dart';

import '../common/matching.dart';
import '../common/port_exception.dart';
import 'ha_model.dart';
import 'ha_ports.dart';

/// Shared state of the Home Assistant tools: the API, the approved
/// entities and the error state.
final class HaContext {
  /// Creates the context. [onError] / [onRecovered] connect the error state
  /// to the app (usually `ToolRegistry.reportError` / `clearError`).
  HaContext(this.api, this.store, {this.onError, this.onRecovered});

  /// Home Assistant access.
  final HaApi api;

  /// The entities the user approved.
  final HaEntityStore store;

  /// Called when the token is rejected (permanent until the setup changes).
  final void Function(String message, PortErrorKind kind)? onError;

  /// Called after the first success following [onError].
  final void Function()? onRecovered;

  bool _failed = false;

  /// Runs [body]; a rejected token pauses the integration, the next success
  /// lifts the pause. Temporary failures (offline, 5xx) do not pause.
  Future<T> guard<T>(Future<T> Function() body) async {
    try {
      final result = await body();
      if (_failed) {
        _failed = false;
        onRecovered?.call();
      }
      return result;
    } on PortException catch (e) {
      if (e.kind == PortErrorKind.permissionDenied && !_failed) {
        _failed = true;
        onError?.call(e.message, e.kind);
      }
      rethrow;
    }
  }

  /// Ids of the approved entities with "always confirm".
  Future<Set<String>> confirmIds() async => {
    for (final e in await store.load())
      if (e.alwaysConfirm) e.entityId,
  };

  /// The entity that [query] (name, "room name" or entity id) names among
  /// the approved ones. Throws `notFound` for none and `rejected` for
  /// several candidates ("Mehrdeutig").
  Future<HaEntity> resolve(String query) async {
    final all = await store.load();
    final lower = query.trim().toLowerCase();
    for (final e in all) {
      if (e.entityId == lower) return e;
    }
    var m = bestMatches(
      query,
      all,
      (e) => [e.name, '${e.area ?? ''} ${e.name}'],
    );
    if (m.best.isEmpty) m = _byTypeAndRoom(query, all);
    if (m.best.isEmpty) {
      throw PortException(
        PortErrorKind.notFound,
        all.isEmpty
            ? 'Es sind keine Home-Assistant-Geräte freigegeben.'
            : 'Kein freigegebenes Gerät „$query“. Mit ha__list_entities '
                  'nachsehen.',
      );
    }
    if (m.best.length > 1) {
      throw PortException(
        PortErrorKind.rejected,
        'Mehrdeutig: „$query“ passt zu '
        '${m.best.map((e) => '„${e.name}“${e.area == null ? '' : ' (${e.area})'}').join(', ')}. '
        'Bitte nachfragen.',
      );
    }
    return m.best.first;
  }

  /// „Lampe Wohnzimmer“ for a device called „Licht Wohnzimmer“ (WP135 B):
  /// when the name does not match, the type word of the query (any language,
  /// see `haDomainsIn`) selects the domain and the rest the room or name.
  /// Without a rest („die Lampe“) every device of the type is a candidate:
  /// a single one is taken, several stay „Mehrdeutig“.
  Matches<HaEntity> _byTypeAndRoom(String query, List<HaEntity> all) {
    final domains = haDomainsIn(query);
    if (domains.isEmpty) return (score: 0, best: const <HaEntity>[]);
    final ofType = [
      for (final e in all)
        if (domains.contains(e.domain)) e,
    ];
    final rest = haWithoutTypeWords(query);
    if (rest.isEmpty || ofType.isEmpty) return (score: 0, best: ofType);
    return bestMatches(rest, ofType, (e) => [e.name, e.area ?? '']);
  }
}
