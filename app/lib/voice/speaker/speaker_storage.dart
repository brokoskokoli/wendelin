import 'dart:convert';

import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// [SpeakerProfileStore] in the [SecretStore] (Android Keystore, WP60,
/// WP92a): voice embeddings are biometric data, so they are encrypted like
/// API keys and never land in SQLite, logs, the audit trail or an export
/// (the audit export is an allow-list, backup is off). Only embeddings are
/// stored, never raw audio.
final class SecretSpeakerProfileStore implements SpeakerProfileStore {
  /// Creates the store.
  SecretSpeakerProfileStore(this.secrets);

  /// Encrypted key-value store.
  final SecretStore secrets;

  /// Key of the profile list (one JSON list).
  static const profilesKey = 'speaker.profiles';

  @override
  Future<List<SpeakerProfile>> load() async {
    final raw = await secrets.read(profilesKey);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List<Object?>;
      return [for (final e in list) ?SpeakerProfile.fromJson(e)];
    } on Object {
      return const []; // damaged: behaves like „nobody enrolled“
    }
  }

  Future<void> _write(List<SpeakerProfile> all) => all.isEmpty
      ? secrets.delete(profilesKey)
      : secrets.write(
          profilesKey,
          jsonEncode([for (final p in all) p.toJson()]),
        );

  @override
  Future<void> save(SpeakerProfile profile) async => _write([
    for (final p in await load())
      if (p.id != profile.id) p,
    profile,
  ]);

  @override
  Future<void> delete(String id) async => _write([
    for (final p in await load())
      if (p.id != id) p,
  ]);

  @override
  Future<void> clear() => secrets.delete(profilesKey);
}
