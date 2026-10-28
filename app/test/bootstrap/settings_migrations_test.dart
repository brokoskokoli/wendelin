import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/bootstrap/storage.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

void main() {
  test(
    'Start-Migrationen löschen den Altwert voice.speechCommunication',
    () async {
      final storage = openInMemoryStorage();
      addTearDown(storage.close);
      final legacy = SettingKey.boolean('voice.speechCommunication');
      final other = SettingKey.boolean('chat.showThinking');
      await storage.settings.set(legacy, true);
      await storage.settings.set(other, true);

      await runSettingsMigrations(storage, InMemorySecretStore());

      expect(await storage.settings.get(legacy), isNull);
      expect(await storage.settings.get(other), isTrue);
    },
  );
}
