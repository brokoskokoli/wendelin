import 'dart:convert';

import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// A person whose voice Wendelin learned (name optional).
final class WakeSpeaker {
  /// Creates a speaker.
  const WakeSpeaker({required this.id, required this.name});

  /// Stable id (key of the templates).
  final String id;

  /// Display name; empty = „Person n“ in the UI.
  final String name;

  Map<String, Object?> toJson() => {'id': id, 'name': name};
}

/// [WakeTemplateStore] and the list of speakers in the [SecretStore]
/// (Android Keystore, WP60): personal voice templates are sensitive, so they
/// are encrypted like API keys, never in SQLite, logs or exports. Only
/// embeddings are stored, never raw audio.
final class SecretWakeTemplateStore implements WakeTemplateStore {
  /// Creates the store.
  SecretWakeTemplateStore(this.secrets);

  /// Encrypted key-value store.
  final SecretStore secrets;

  /// Key of the speaker list.
  static const speakersKey = 'wake.speakers';

  /// Prefix of the template keys (`wake.templates.<speakerId>`).
  static const templatePrefix = 'wake.templates.';

  /// Prefix of the „Stopp“ template keys (`wake.stop.<speakerId>`, WP64b).
  static const stopPrefix = 'wake.stop.';

  /// The same store for the keyword „Stopp“ (only listened for while an
  /// answer is spoken): embeddings under [stopPrefix], same encryption.
  late final WakeTemplateStore stop = _PrefixedStore(this, stopPrefix);

  @override
  Future<WakeTemplates?> load(String speakerId) =>
      _load(templatePrefix, speakerId);

  Future<WakeTemplates?> _load(String prefix, String speakerId) async {
    final raw = await secrets.read('$prefix$speakerId');
    if (raw == null) return null;
    try {
      return WakeTemplates.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on Object {
      return null; // damaged: behaves like „not learned“
    }
  }

  @override
  Future<void> save(WakeTemplates templates) =>
      _save(templatePrefix, templates);

  Future<void> _save(String prefix, WakeTemplates templates) => secrets.write(
    '$prefix${templates.speakerId}',
    jsonEncode(templates.toJson()),
  );

  @override
  Future<void> delete(String speakerId) async {
    await secrets.delete('$templatePrefix$speakerId');
    await secrets.delete('$stopPrefix$speakerId');
  }

  /// The learned speakers.
  Future<List<WakeSpeaker>> speakers() async {
    final raw = await secrets.read(speakersKey);
    if (raw == null) return const [];
    try {
      return [
        for (final e in jsonDecode(raw) as List<Object?>)
          if (e is Map<String, Object?> && e['id'] is String)
            WakeSpeaker(id: e['id']! as String, name: '${e['name'] ?? ''}'),
      ];
    } on Object {
      return const [];
    }
  }

  /// Stores the speaker list.
  Future<void> saveSpeakers(List<WakeSpeaker> speakers) => secrets.write(
    speakersKey,
    jsonEncode([for (final s in speakers) s.toJson()]),
  );

  /// Forgets every speaker and all templates („Alles löschen“).
  Future<void> deleteAll() async {
    for (final key in await secrets.listKeys()) {
      if (key == speakersKey ||
          key.startsWith(templatePrefix) ||
          key.startsWith(stopPrefix)) {
        await secrets.delete(key);
      }
    }
  }
}

final class _PrefixedStore implements WakeTemplateStore {
  _PrefixedStore(this._store, this._prefix);

  final SecretWakeTemplateStore _store;
  final String _prefix;

  @override
  Future<WakeTemplates?> load(String speakerId) =>
      _store._load(_prefix, speakerId);

  @override
  Future<void> save(WakeTemplates templates) =>
      _store._save(_prefix, templates);

  @override
  Future<void> delete(String speakerId) =>
      _store.secrets.delete('$_prefix$speakerId');
}
