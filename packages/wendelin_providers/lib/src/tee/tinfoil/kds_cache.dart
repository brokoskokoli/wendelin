import 'dart:typed_data';

import 'package:meta/meta.dart';

/// VCEK certificate and AMD chain of one chip and TCB, as the key
/// distribution service delivers them.
@immutable
final class KdsEntry {
  /// Creates an entry.
  const KdsEntry({
    required this.vcek,
    required this.chain,
    required this.product,
  });

  /// DER of the VCEK.
  final Uint8List vcek;

  /// PEM of ASK and ARK.
  final String chain;

  /// AMD product (`Genoa`, `Milan`, …).
  final String product;
}

/// Keeps [KdsEntry]s across restarts: the AMD KDS answers 429 when asked
/// again too often. Nothing in it is trusted: the Rust check verifies VCEK
/// and chain against the pinned ARK on every attestation.
abstract interface class KdsCache {
  /// The entry of [key], `null` if none (or unreadable).
  Future<KdsEntry?> load(String key);

  /// Stores [entry] under [key].
  Future<void> save(String key, KdsEntry entry);
}

/// In-memory [KdsCache] (default and tests).
final class InMemoryKdsCache implements KdsCache {
  final Map<String, KdsEntry> _entries = {};

  @override
  Future<KdsEntry?> load(String key) async => _entries[key];

  @override
  Future<void> save(String key, KdsEntry entry) async => _entries[key] = entry;
}
