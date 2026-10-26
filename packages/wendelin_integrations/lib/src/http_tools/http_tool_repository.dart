import 'dart:async';
import 'dart:convert';

import 'package:wendelin_core/wendelin_core.dart';

import 'http_secret_refs.dart';
import 'http_tool_definition.dart';
import 'http_transport.dart';

/// Where the HTTP-tool definitions are persisted (JSON of each, no
/// secrets). The app implements it with its settings (`http.tools`).
abstract interface class HttpToolStore {
  /// The stored definitions as JSON; empty if there are none.
  Future<List<Map<String, Object?>>> read();

  /// Replaces the stored definitions.
  Future<void> write(List<Map<String, Object?>> definitions);
}

/// Where the secrets of the HTTP tools live, addressed by secret reference
/// (`<id>.bearer`, `<id>.h.<header>`). The app maps the references into a
/// namespace of the device `SecretStore` (`http_tool.`), so an HTTP tool
/// can never touch another secret.
abstract interface class HttpToolSecretVault {
  /// The secret of [ref], or `null`.
  Future<String?> read(String ref);

  /// Stores [value] under [ref].
  Future<void> write(String ref, String value);

  /// Removes [ref] (no error if missing).
  Future<void> delete(String ref);

  /// All references currently stored.
  Future<Set<String>> refs();
}

/// [HttpToolSecrets] that answers from [pending] first (secrets typed in
/// the editor but not saved yet, `null` = removed) and falls back to
/// [inner]. Used by the editor's test run.
final class PendingHttpToolSecrets implements HttpToolSecrets {
  /// Creates the overlay.
  PendingHttpToolSecrets(this.inner, Map<String, String?> pending)
    : _pending = Map.of(pending);

  /// Stored secrets.
  final HttpToolSecrets inner;

  final Map<String, String?> _pending;

  @override
  Future<String?> read(String secretRef) async =>
      _pending.containsKey(secretRef)
      ? _pending[secretRef]
      : inner.read(secretRef);

  @override
  String toString() => 'PendingHttpToolSecrets(<verborgen>)';
}

/// The user's HTTP-tool definitions ([HttpToolStore]) and their secrets
/// ([HttpToolSecretVault]).
///
/// Every definition only references secrets below its own id
/// (`<id>.bearer`, `<id>.h.<header>`); imports are rewritten to that
/// scheme, so an imported definition cannot read another tool's secret.
final class HttpToolRepository {
  /// Creates the repository.
  HttpToolRepository({
    required this.store,
    required this.secrets,
    required this.ids,
    this.onInvalid,
  });

  /// Where the definitions live.
  final HttpToolStore store;

  /// Where the secrets live.
  final HttpToolSecretVault secrets;

  /// New ids for definitions.
  final IdGenerator ids;

  /// Gets stored definitions that could not be read (they are skipped).
  final void Function(String message)? onInvalid;

  final StreamController<void> _changes = StreamController<void>.broadcast();
  List<HttpToolDefinition>? _cache;
  Future<void> _queue = Future.value();

  /// Emits after every change.
  Stream<void> get changes => _changes.stream;

  /// The stored definitions, in order.
  Future<List<HttpToolDefinition>> definitions() async =>
      List.unmodifiable(_cache ??= await _read());

  Future<List<HttpToolDefinition>> _read() async {
    final raw = await store.read();
    final out = <HttpToolDefinition>[];
    for (final json in raw) {
      try {
        final d = HttpToolDefinition.fromJson(json);
        _checkRefs(d);
        validateHttpToolSet([...out, d]);
        out.add(d);
      } on FormatException catch (e) {
        onInvalid?.call(e.message);
      }
    }
    return out;
  }

  /// A fresh id for a new definition.
  String newId() => ids.next();

  /// Whether the secret [ref] is stored.
  Future<bool> hasSecret(String ref) async =>
      ref.isNotEmpty && await secrets.read(ref) != null;

  /// Adds or replaces [definition] (by id). [secretValues] maps secret
  /// references to new values (`null` deletes). Secrets the definition no
  /// longer references are deleted. Throws [FormatException] if the
  /// definition is invalid or its name is taken.
  Future<void> save(
    HttpToolDefinition definition, {
    Map<String, String?> secretValues = const {},
  }) => _locked(() async {
    _checkRefs(definition);
    final current = await definitions();
    final next = [
      for (final d in current)
        if (d.id == definition.id) definition else d,
      if (!current.any((d) => d.id == definition.id)) definition,
    ];
    validateHttpToolSet(next);
    final used = httpSecretRefs(definition.auth);
    for (final MapEntry(key: ref, value: value) in secretValues.entries) {
      if (!used.contains(ref)) continue;
      value == null || value.isEmpty
          ? await secrets.delete(ref)
          : await secrets.write(ref, value);
    }
    await _deleteSecrets(definition.id, keep: used);
    await _write(next);
  });

  /// Deletes the definition [id] and all its secrets.
  Future<void> delete(String id) => _locked(() async {
    final current = await definitions();
    await _deleteSecrets(id);
    await _write([
      for (final d in current)
        if (d.id != id) d,
    ]);
  });

  /// Deletes the secrets of the definition [id] unless it is still stored
  /// (follow-up cleanup of the sync, ADR 0012 §2).
  Future<void> deleteSecretsOfRemoved(String id) => _locked(() async {
    if ((await definitions()).any((d) => d.id == id)) return;
    await _deleteSecrets(id);
  });

  /// Export document (JSON text) without secrets.
  Future<String> exportJson() async =>
      const JsonEncoder.withIndent('  ')
          .convert(exportHttpTools(await definitions()));

  /// Imports the definitions of an export [text]; each gets a new id and
  /// secret references of its own (the secrets must be entered again) and
  /// `autoRun` off (asks again until the user switches it on) and
  /// „Kann unsichere Inhalte enthalten“ on. Does not
  /// switch the HTTP integrations on. Returns the imported definitions. Throws [FormatException] with a
  /// readable message (invalid JSON, invalid definition, name taken).
  Future<List<HttpToolDefinition>> importJson(String text) => _locked(() async {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const FormatException('Kein gültiges JSON');
    }
    if (json is! Map<String, Object?>) {
      throw const FormatException('Export-Objekt erwartet');
    }
    final imported = [
      for (final d in importHttpTools(json)) _rekey(d, newId()),
    ];
    imported.forEach(_checkRefs);
    final next = [...await definitions(), ...imported];
    validateHttpToolSet(next);
    await _write(next);
    return imported;
  });

  /// [d] with [id] and secret references in its own namespace.
  static HttpToolDefinition _rekey(HttpToolDefinition d, String id) {
    final auth = switch (d.auth) {
      ApiKeyAuth(headerName: null) => ApiKeyAuth(httpBearerRef(id)),
      ApiKeyAuth(:final headerName?) => CustomHeadersAuth({
        headerName: httpHeaderRef(id, headerName),
      }),
      CustomHeadersAuth(:final secretRefsByHeader) => CustomHeadersAuth({
        for (final h in secretRefsByHeader.keys) h: httpHeaderRef(id, h),
      }),
      final other => other,
    };
    // „Ohne Nachfrage“ und „keine unsicheren Inhalte“ entscheidet der Nutzer
    // auf diesem Gerät selbst (eine Datei darf sich nicht für sicher
    // erklären).
    final json = {...d.toJson(), 'id': id, 'auth': auth.toJson()}
      ..remove('autoRun')
      ..remove('mayContainUntrustedContent');
    return HttpToolDefinition.fromJson(json);
  }

  static void _checkRefs(HttpToolDefinition d) {
    for (final ref in httpSecretRefs(d.auth)) {
      if (!ref.startsWith('${d.id}.')) {
        throw FormatException(
          'HTTP-Tool „${d.name}“: Secret-Referenz gehört nicht zum Tool',
        );
      }
    }
  }

  Future<void> _deleteSecrets(String id, {Set<String> keep = const {}}) async {
    final prefix = '$id.';
    for (final ref in await secrets.refs()) {
      if (ref.startsWith(prefix) && !keep.contains(ref)) {
        await secrets.delete(ref);
      }
    }
  }

  Future<void> _write(List<HttpToolDefinition> next) async {
    await store.write([for (final d in next) d.toJson()]);
    _cache = List.of(next);
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<T> _locked<T>(Future<T> Function() body) {
    final run = _queue.then((_) => body());
    _queue = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  /// Closes [changes].
  Future<void> dispose() => _changes.close();
}
