import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/speech_communication_migration.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

/// Raw key, independent of the (kept) legacy constant.
final _raw = SettingKey.boolean('voice.speechCommunication');
final _other = SettingKey.boolean('chat.showThinking');

void main() {
  late WendelinStorage storage;

  setUp(() => storage = openInMemoryStorage());

  test('alter Wert true: nach der Migration weg, Rest unberührt', () async {
    await storage.settings.set(_raw, true);
    await storage.settings.set(_other, true);
    await migrateRemovedSpeechCommunication(storage.settings);
    expect(await storage.settings.get(_raw), isNull);
    expect(await storage.settings.get(_other), isTrue);
  });

  test('ohne alten Wert: kein Fehler, nichts gesetzt', () async {
    await migrateRemovedSpeechCommunication(storage.settings);
    expect(await storage.settings.get(_raw), isNull);
  });

  test('zweimal: idempotent', () async {
    await storage.settings.set(_raw, false);
    await migrateRemovedSpeechCommunication(storage.settings);
    await migrateRemovedSpeechCommunication(storage.settings);
    expect(await storage.settings.get(_raw), isNull);
  });
}
