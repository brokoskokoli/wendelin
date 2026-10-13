import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'saf_list_file_port.dart' show decodeUtf8KeepingBom;

/// Name of the platform channel of the Obsidian vault (Kotlin side:
/// `VaultChannel.kt`).
const vaultChannelName = 'app.wendelin/vault';

/// [VaultPort] on an Android Storage Access Framework tree: the vault
/// folder chosen with `ACTION_OPEN_DOCUMENT_TREE` ([VaultAccess.pick]),
/// with a persisted read/write grant.
///
/// - Paths are checked with [VaultPath] here and resolved segment by
///   segment on the native side (never `..`).
/// - Content travels as bytes; UTF-8 is decoded here and a BOM is kept.
/// - `write` replaces the content in one call with mode `wt` (SAF has no
///   atomic rename over an existing document); missing folders are
///   created.
/// - `list` delivers modification time and size with one query, so the
///   index sync needs no extra calls.
/// - Every call has a [timeout]; a hanging provider becomes
///   `PortException(unavailable)` instead of blocking the write queue.
final class SafVaultPort implements VaultPort {
  /// Creates the port on the tree URI [tree] reads (`null` = no vault
  /// chosen); `channel` is injectable for tests.
  SafVaultPort({
    required this.tree,
    this._channel = const MethodChannel(vaultChannelName),
    this.timeout = const Duration(seconds: 10),
  });

  /// Current vault tree URI.
  final String? Function() tree;

  final MethodChannel _channel;

  /// Limit per platform call.
  final Duration timeout;

  @override
  Future<List<VaultEntry>> list(String folder) async {
    final path = VaultPath.normalize(folder, allowRoot: true);
    final raw = await _call<List<Object?>>('list', path) ?? const [];
    return [
      for (final e in raw.cast<Map<Object?, Object?>>())
        if (e['name'] case final String name
            when name.isNotEmpty && !name.contains('/'))
          VaultEntry(
            path: VaultPath.join(path, name),
            isFolder: e['folder'] == true,
            modifiedAt: _time(e['modified']),
            size: e['folder'] == true ? null : e['size'] as int?,
          ),
    ];
  }

  @override
  Future<String> read(String path) async {
    final p = VaultPath.normalize(path);
    final bytes = await _call<Uint8List>('read', p);
    if (bytes == null) throw _notFound(p);
    try {
      return decodeUtf8KeepingBom(bytes);
    } on FormatException {
      throw PortException(PortErrorKind.failed, '„$p“ ist kein UTF-8-Text.');
    }
  }

  @override
  Future<void> write(String path, String content) async => _call<void>(
    'write',
    VaultPath.normalize(path),
    bytes: Uint8List.fromList(utf8.encode(content)),
  );

  @override
  Future<void> create(String path, String content) async => _call<void>(
    'create',
    VaultPath.normalize(path),
    bytes: Uint8List.fromList(utf8.encode(content)),
  );

  @override
  Future<void> delete(String path) async =>
      _call<void>('delete', VaultPath.normalize(path));

  @override
  Future<bool> exists(String path) async =>
      await _stat(VaultPath.normalize(path, allowRoot: true)) != null;

  @override
  Future<DateTime> modifiedAt(String path) async {
    final p = VaultPath.normalize(path);
    final stat = await _file(p);
    // Providers without a modification time: the index then re-reads the
    // note only when its size changes (documented limit).
    return _time(stat['modified']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  @override
  Future<int> size(String path) async {
    final p = VaultPath.normalize(path);
    return ((await _file(p))['size'] as int?) ?? 0;
  }

  Future<Map<Object?, Object?>?> _stat(String path) =>
      _call<Map<Object?, Object?>>('stat', path);

  Future<Map<Object?, Object?>> _file(String path) async {
    final stat = await _stat(path);
    if (stat == null || stat['folder'] == true) throw _notFound(path);
    return stat;
  }

  static DateTime? _time(Object? ms) =>
      ms is int ? DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true) : null;

  static PortException _notFound(String path) =>
      PortException(PortErrorKind.notFound, '„$path“ gibt es nicht');

  Future<T?> _call<T>(String method, String path, {Uint8List? bytes}) async {
    final uri = tree();
    if (uri == null) {
      throw const PortException(
        PortErrorKind.unavailable,
        'Kein Obsidian-Vault gewählt (Einstellungen → Obsidian).',
      );
    }
    try {
      return await _channel
          .invokeMethod<T>(method, {'tree': uri, 'path': path, 'bytes': ?bytes})
          .timeout(timeout);
    } on TimeoutException {
      throw const PortException(
        PortErrorKind.unavailable,
        'Der Vault antwortet nicht.',
      );
    } on PlatformException catch (e) {
      throw vaultError(e.code, path);
    } on MissingPluginException {
      throw const PortException(
        PortErrorKind.unsupported,
        'Vault-Zugriff ist auf diesem Gerät nicht verfügbar.',
      );
    }
  }
}

/// German [PortException] for a native vault error [code] at [path].
PortException vaultError(String code, String path) => switch (code) {
  'notFound' => SafVaultPort._notFound(path),
  'exists' => PortException(PortErrorKind.rejected, '„$path“ gibt es schon'),
  'isFolder' => PortException(PortErrorKind.rejected, '„$path“ ist ein Ordner'),
  'rejected' => PortException(
    PortErrorKind.rejected,
    'Pfad „$path“ ist nicht erlaubt',
  ),
  'tooLarge' => PortException(PortErrorKind.rejected, '„$path“ ist zu groß'),
  'unsupported' => const PortException(
    PortErrorKind.unsupported,
    'Auf diesem Gerät gibt es keine Ordnerauswahl.',
  ),
  'permissionDenied' => const PortException(
    PortErrorKind.permissionDenied,
    'Kein Zugriff mehr auf den Vault. Bitte in den Einstellungen → '
    'Obsidian neu wählen.',
  ),
  _ => PortException(
    PortErrorKind.failed,
    '„$path“ konnte nicht gelesen oder geschrieben werden.',
  ),
};

/// The chosen vault folder: tree URI and display name.
typedef PickedVault = ({String uri, String name});

/// Choosing the vault folder (SAF tree with persisted grant), checking and
/// releasing the grant.
class VaultAccess {
  /// Creates the access; `channel` is injectable for tests.
  const VaultAccess({this._channel = const MethodChannel(vaultChannelName)});

  final MethodChannel _channel;

  /// Lets the user pick the vault folder; `null` if cancelled.
  Future<PickedVault?> pick() async {
    final raw = await _invoke<Map<Object?, Object?>>('pickTree', const {});
    final uri = raw?['uri'];
    if (uri is! String) return null;
    final name = raw?['name'];
    return (uri: uri, name: name is String && name.isNotEmpty ? name : 'Vault');
  }

  /// Whether the persisted grant for [tree] is still held.
  Future<bool> hasAccess(String tree) async =>
      await _invoke<bool>('hasAccess', {'tree': tree}) ?? false;

  /// Gives up the grant of [tree] (another vault chosen, vault removed).
  Future<void> release(String tree) => _invoke<void>('release', {'tree': tree});

  Future<T?> _invoke<T>(String method, Map<String, Object?> args) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw vaultError(e.code, '');
    } on MissingPluginException {
      throw const PortException(
        PortErrorKind.unsupported,
        'Ordnerauswahl ist auf diesem Gerät nicht verfügbar.',
      );
    }
  }
}
