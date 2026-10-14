import 'package:meta/meta.dart';

/// What the app pinned of an attested provider (concept: Pinning).
@immutable
final class AttestationPin {
  /// Creates a pin.
  const AttestationPin({
    required this.keysetDigest,
    required this.composeHash,
    required this.pinnedAt,
    this.repoCommit,
  });

  /// `workload_keyset_digest`.
  final String keysetDigest;

  /// `sha256` of `app_compose`.
  final String composeHash;

  /// `source_provenance.repo_commit`, if given.
  final String? repoCommit;

  /// When the pin was set.
  final DateTime pinnedAt;

  /// Whether [other] differs in a pinned value (time ignored).
  bool changedBy(AttestationPin other) =>
      other.keysetDigest != keysetDigest ||
      other.composeHash != composeHash ||
      other.repoCommit != repoCommit;

  /// JSON for storage.
  Map<String, Object?> toJson() => {
    'keysetDigest': keysetDigest,
    'composeHash': composeHash,
    if (repoCommit != null) 'repoCommit': repoCommit,
    'pinnedAt': pinnedAt.toUtc().toIso8601String(),
  };

  /// Reads [toJson]; throws [FormatException].
  factory AttestationPin.fromJson(Map<String, Object?> json) {
    final digest = json['keysetDigest'];
    final compose = json['composeHash'];
    final at = json['pinnedAt'];
    if (digest is! String || compose is! String || at is! String) {
      throw const FormatException('AttestationPin: Felder fehlen');
    }
    return AttestationPin(
      keysetDigest: digest,
      composeHash: compose,
      repoCommit: json['repoCommit'] as String?,
      pinnedAt: DateTime.parse(at),
    );
  }
}

/// Persists the pin per provider profile (implemented in the app via
/// storage).
abstract interface class AttestationPinStore {
  /// The pin of [profileId], or `null` if never attested.
  Future<AttestationPin?> load(String profileId);

  /// Stores [pin] for [profileId].
  Future<void> save(String profileId, AttestationPin pin);
}

/// In-memory [AttestationPinStore] for tests and demo mode.
final class InMemoryAttestationPinStore implements AttestationPinStore {
  final Map<String, AttestationPin> _pins = {};

  @override
  Future<AttestationPin?> load(String profileId) async => _pins[profileId];

  @override
  Future<void> save(String profileId, AttestationPin pin) async =>
      _pins[profileId] = pin;
}
