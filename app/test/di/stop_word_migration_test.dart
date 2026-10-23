import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/stop_word_migration.dart';
import 'package:wendelin/di/voice_settings_providers.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// Throws on every call, like a damaged keystore.
class _BrokenSecrets implements SecretStore {
  @override
  Future<Set<String>> listKeys() async => throw StateError('Keystore kaputt');

  @override
  Future<String?> read(String key) async => throw StateError('kaputt');

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('kaputt');

  @override
  Future<void> delete(String key) async => throw StateError('kaputt');
}

final _stringKey = SettingKey.string(voiceSettingsKey.name);

void main() {
  late WendelinStorage storage;

  setUp(() => storage = openInMemoryStorage());

  Future<Map<String, Object?>?> rawSettings() async {
    final raw = await storage.settings.get(
      SettingKey<Map<String, Object?>>(
        voiceSettingsKey.name,
        encode: (m) => m,
        decode: (j) => j as Map<String, Object?>,
      ),
    );
    return raw;
  }

  test(
    'löscht wake.stop.* und stopClosesOverlay, lässt den Rest unberührt',
    () async {
      final secrets = InMemorySecretStore({
        'wake.stop.a': 'x',
        'wake.stop.b': 'y',
        'wake.templates.a': 'keep',
        'wake.speakers': 'keep',
        'other.key': 'keep',
      });
      await storage.settings.set(
        SettingKey<Map<String, Object?>>(
          voiceSettingsKey.name,
          encode: (m) => m,
          decode: (j) => j as Map<String, Object?>,
        ),
        {'stopClosesOverlay': false, 'conversationMode': true},
      );
      await migrateRemovedStopWord(storage.settings, secrets);
      expect(await secrets.listKeys(), {
        'other.key',
        'wake.speakers',
        'wake.templates.a',
      });
      expect(await rawSettings(), {'conversationMode': true});
      final loaded = await storage.settings.get(voiceSettingsKey);
      expect(loaded!.conversationMode, isTrue);
    },
  );

  test('ein zweiter Lauf ändert nichts mehr', () async {
    final secrets = InMemorySecretStore({'wake.stop.a': 'x', 'k': 'v'});
    await migrateRemovedStopWord(storage.settings, secrets);
    await migrateRemovedStopWord(storage.settings, secrets);
    expect(await secrets.listKeys(), {'k'});
  });

  test('keine Altdaten: nichts wird angelegt', () async {
    final secrets = InMemorySecretStore({'wake.templates.a': 'keep'});
    await migrateRemovedStopWord(storage.settings, secrets);
    expect(await secrets.listKeys(), {'wake.templates.a'});
    expect(await rawSettings(), isNull);
    expect(await storage.settings.get(voiceSettingsKey), isNull);
  });

  test('gespeicherte Einstellungen ohne Altschlüssel bleiben gleich', () async {
    await storage.settings.set(
      voiceSettingsKey,
      const VoiceSettings(conversationMode: true),
    );
    final before = await rawSettings();
    await migrateRemovedStopWord(storage.settings, InMemorySecretStore());
    expect(await rawSettings(), before);
  });

  test('kaputtes voice.settings (kein Objekt): wirft nicht, bleibt liegen, '
      'Stopp-Vorlagen sind trotzdem weg', () async {
    await storage.settings.set(_stringKey, 'kaputt');
    final secrets = InMemorySecretStore({'wake.stop.a': 'x'});
    await migrateRemovedStopWord(storage.settings, secrets);
    expect(await secrets.listKeys(), isEmpty);
    expect(await storage.settings.get(_stringKey), 'kaputt');
  });

  test('Secret-Store wirft: Einstellung wird trotzdem bereinigt', () async {
    await storage.settings.set(
      SettingKey<Map<String, Object?>>(
        voiceSettingsKey.name,
        encode: (m) => m,
        decode: (j) => j as Map<String, Object?>,
      ),
      {'stopClosesOverlay': true},
    );
    await migrateRemovedStopWord(storage.settings, _BrokenSecrets());
    expect(await rawSettings(), isEmpty);
  });
}
