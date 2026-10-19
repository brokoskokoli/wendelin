import 'dart:convert';

import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// [PersonSettingsStore] in the [SecretStore] (WP92b): the address is a name
/// and the settings tell which profile and memory a person uses, so they are
/// encrypted like the voice profiles and never land in SQLite, logs, the
/// audit trail or an export.
final class SecretPersonSettingsStore implements PersonSettingsStore {
  /// Creates the store.
  SecretPersonSettingsStore(this.secrets);

  /// Encrypted key-value store.
  final SecretStore secrets;

  /// Key of the settings list (one JSON list).
  static const settingsKey = 'speaker.persons';

  @override
  Future<Map<String, PersonSettings>> load() async {
    final raw = await secrets.read(settingsKey);
    if (raw == null) return const {};
    try {
      final list = jsonDecode(raw) as List<Object?>;
      final all = <String, PersonSettings>{};
      for (final e in list) {
        final s = PersonSettings.fromJson(e);
        if (s != null) all[s.personId] = s;
      }
      return all;
    } on Object {
      return const {}; // damaged: everyone gets the defaults
    }
  }

  Future<void> _write(Map<String, PersonSettings> all) => all.isEmpty
      ? secrets.delete(settingsKey)
      : secrets.write(
          settingsKey,
          jsonEncode([for (final s in all.values) s.toJson()]),
        );

  @override
  Future<void> save(PersonSettings settings) async =>
      _write({...await load(), settings.personId: settings});

  @override
  Future<void> delete(String personId) async =>
      _write({...await load()}..remove(personId));

  @override
  Future<void> clear() => secrets.delete(settingsKey);
}
