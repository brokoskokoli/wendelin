import 'speaker_profile.dart';

/// Persistent store of enrolled [SpeakerProfile]s (WP92a). The app keeps
/// them encrypted (Keystore); implementations never write the embeddings
/// to plain files, logs, the audit trail or an export, and [clear] removes
/// everything.
abstract interface class SpeakerProfileStore {
  /// All profiles (malformed entries are skipped).
  Future<List<SpeakerProfile>> load();

  /// Adds [profile] or replaces the one with the same id.
  Future<void> save(SpeakerProfile profile);

  /// Removes the profile [id] (no error if it does not exist).
  Future<void> delete(String id);

  /// Removes all profiles.
  Future<void> clear();
}
