import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'app_settings.dart';
import 'providers.dart';
import 'user_integrations.dart';

/// Namespace of the HTTP-tool secrets in the [SecretStore]. A secret
/// reference `r` of a definition is stored under `http_tool.r`, so an
/// HTTP tool can never read another secret (provider keys, Bring!).
const httpToolSecretNamespace = 'http_tool.';

/// Secret reference of the bearer token of the definition [id].
String httpBearerRef(String id) => '$id.bearer';

/// Secret reference of the secret header [header] of the definition [id].
String httpHeaderRef(String id, String header) =>
    '$id.h.${header.toLowerCase()}';

/// The secret references [auth] uses.
Set<String> httpSecretRefs(AuthMethod auth) => switch (auth) {
  ApiKeyAuth(:final secretRef) => {secretRef},
  CustomHeadersAuth(:final secretRefsByHeader) => {
    ...secretRefsByHeader.values,
  },
  _ => const {},
};

/// [HttpToolSecrets] on the app's [SecretStore] (Android Keystore). Reads
/// only inside [httpToolSecretNamespace]. Passes `httpToolSecretsContract`.
final class SecretStoreHttpToolSecrets implements HttpToolSecrets {
  /// Creates the adapter.
  const SecretStoreHttpToolSecrets(this.store);

  /// The device secret store.
  final SecretStore store;

  /// Key of [ref] in [store].
  static String keyOf(String ref) => '$httpToolSecretNamespace$ref';

  @override
  Future<String?> read(String secretRef) async {
    if (secretRef.isEmpty) return null;
    return store.read(keyOf(secretRef));
  }

  @override
  String toString() => 'SecretStoreHttpToolSecrets(<verborgen>)';
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

/// Settings key of the stored definitions (JSON of each, no secrets).
final httpToolsSetting = SettingKey<List<Map<String, Object?>>>(
  'http.tools',
  encode: (list) => list,
  decode: (json) {
    if (json is! List) throw const FormatException('http.tools: Liste');
    return [
      for (final e in json)
        e is Map<String, Object?>
            ? e
            : throw const FormatException('http.tools: Objekt erwartet'),
    ];
  },
  defaultValue: const [],
);

/// The user's HTTP-tool definitions (settings) and their secrets
/// ([SecretStore], namespace [httpToolSecretNamespace]).
///
/// Every definition only references secrets below its own id
/// (`<id>.bearer`, `<id>.h.<header>`); imports are rewritten to that
/// scheme, so an imported definition cannot read another tool's secret.
final class HttpToolRepository {
  /// Creates the repository.
  HttpToolRepository({
    required this.settings,
    required this.secrets,
    required this.ids,
    this.onInvalid,
  });

  /// Where the definitions live.
  final SettingsRepository settings;

  /// Where the secrets live.
  final SecretStore secrets;

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
    final raw = await settings.get(httpToolsSetting) ?? const [];
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
      await secrets.read(SecretStoreHttpToolSecrets.keyOf(ref)) != null;

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
      final key = SecretStoreHttpToolSecrets.keyOf(ref);
      value == null || value.isEmpty
          ? await secrets.delete(key)
          : await secrets.write(key, value);
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
  /// secret references of its own (the secrets must be entered again).
  /// Returns the imported definitions. Throws [FormatException] with a
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
    return HttpToolDefinition.fromJson({
      ...d.toJson(),
      'id': id,
      'auth': auth.toJson(),
    });
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
    final prefix = SecretStoreHttpToolSecrets.keyOf('$id.');
    final keepKeys = {
      for (final r in keep) SecretStoreHttpToolSecrets.keyOf(r),
    };
    for (final key in await secrets.listKeys()) {
      if (key.startsWith(prefix) && !keepKeys.contains(key)) {
        await secrets.delete(key);
      }
    }
  }

  Future<void> _write(List<HttpToolDefinition> next) async {
    await settings.set(httpToolsSetting, [for (final d in next) d.toJson()]);
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

/// [UserIntegrationSource] of the HTTP tools (ADR 0011 §6, ADR 0012): the
/// integrations `http` and `http_sensitive` built from the
/// [HttpToolRepository]. An integration is only offered while it has
/// tools; an unchanged one is returned as the identical object.
final class HttpToolSource implements UserIntegrationSource {
  /// Creates the source.
  HttpToolSource(this.repository, this.runner);

  /// The stored definitions.
  final HttpToolRepository repository;

  /// Executes the calls.
  final HttpToolRunner runner;

  final Map<bool, (List<HttpToolDefinition>, HttpToolsIntegration)> _built = {};

  @override
  UserIntegrationKind get kind => UserIntegrationKind.http;

  @override
  Stream<void> get changes => repository.changes;

  @override
  Future<List<Integration>> load() async {
    final all = await repository.definitions();
    final out = <Integration>[];
    for (final sensitive in [false, true]) {
      final defs = [
        for (final d in all)
          if (d.enabled && d.sensitive == sensitive) d,
      ];
      if (defs.isEmpty) {
        _built.remove(sensitive);
        continue;
      }
      final previous = _built[sensitive];
      if (previous != null && listEquals(previous.$1, defs)) {
        out.add(previous.$2);
        continue;
      }
      final integration = HttpToolsIntegration(
        definitions: defs,
        runner: runner,
        sensitive: sensitive,
      );
      _built[sensitive] = (defs, integration);
      out.add(integration);
    }
    return out;
  }

  @override
  Future<void> deleteSecrets(IntegrationRemoval removal) async {
    final integration = unwrapHttpTools(removal.integration);
    if (integration == null) return;
    for (final d in integration.definitions) {
      if (removal.toolNames.contains(d.toolName)) {
        await repository.deleteSecretsOfRemoved(d.id);
      }
    }
  }
}

/// [integration] as [HttpToolsIntegration], if it is one.
HttpToolsIntegration? unwrapHttpTools(Integration integration) =>
    switch (integration) {
      final HttpToolsIntegration h => h,
      _ => null,
    };

/// Builds the runner of the HTTP tools for a secret source (the editor's
/// test run passes secrets that are not saved yet). Tests override it
/// with a `MockClient` transport.
typedef HttpToolRunnerFactory = HttpToolRunner Function(
  HttpToolSecrets secrets,
);

/// Runner factory: pinned `dart:io` transport (ADR 0011 §3).
final httpToolRunnerFactoryProvider = Provider<HttpToolRunnerFactory>((ref) {
  final clock = ref.watch(clockProvider);
  return (secrets) => HttpToolRunner(
    transport: PinnedHttpToolTransport(),
    secrets: secrets,
    clock: clock,
  );
});

/// Stored secrets of the HTTP tools.
final httpToolSecretsProvider = Provider<HttpToolSecrets>(
  (ref) => SecretStoreHttpToolSecrets(ref.watch(secretStoreProvider)),
);

/// The user's HTTP-tool definitions.
final httpToolRepositoryProvider = Provider<HttpToolRepository>((ref) {
  final repository = HttpToolRepository(
    settings: ref.watch(storageProvider).settings,
    secrets: ref.watch(secretStoreProvider),
    ids: ref.watch(idGeneratorProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

/// The HTTP tools as user-defined integrations.
final httpToolSourceProvider = Provider<HttpToolSource>(
  (ref) => HttpToolSource(
    ref.watch(httpToolRepositoryProvider),
    ref.watch(httpToolRunnerFactoryProvider)(
      ref.watch(httpToolSecretsProvider),
    ),
  ),
);

/// Switches the integration of [definition] on before its first tool is
/// saved, so a newly created tool is usable at once (creating it is the
/// explicit setup, ADR 0012). An integration that is already registered
/// keeps the user's switch.
Future<void> enableHttpIntegrationIfNew(
  SettingsRepository settings,
  Set<String> registeredIds,
  HttpToolDefinition definition,
) async {
  final id = definition.sensitive
      ? HttpToolsIntegration.sensitiveId
      : HttpToolsIntegration.plainId;
  if (registeredIds.contains(id)) return;
  await settings.set(AppSettings.integrationEnabled(id), true);
}
