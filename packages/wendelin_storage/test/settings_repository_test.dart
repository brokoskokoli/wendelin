import 'package:test/test.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'support/storage_fixture.dart';

enum _Mode { voice, text }

final _mode = SettingKey<_Mode>(
  'ui.mode',
  encode: (m) => m.name,
  decode: (v) => _Mode.values.byName(v! as String),
  defaultValue: _Mode.voice,
);

void main() {
  late WendelinStorage storage;
  late SettingsRepository repo;

  setUp(() {
    storage = openTestStorage().storage;
    repo = storage.settings;
  });
  tearDown(() => storage.close());

  test('einfache Typen: Default, set, get, überschreiben, remove', () async {
    final wake = SettingKey.boolean('voice.wakeWord', defaultValue: true);
    final name = SettingKey.string('assistant.name');
    final days = SettingKey.integer('audit.retentionDays', defaultValue: 30);
    final rate = SettingKey.decimal('tts.rate');
    final rules = SettingKey.json('routing.rules');

    expect(await repo.get(wake), isTrue);
    expect(await repo.get(name), isNull);
    expect(await repo.get(days), 30);

    await repo.set(wake, false);
    await repo.set(name, 'Wendelin');
    await repo.set(days, 7);
    await repo.set(rate, 1.25);
    await repo.set(rules, {
      'default': 'claude',
      'rules': [
        {'if': 'tee', 'then': 'phala'},
      ],
    });
    expect(await repo.get(wake), isFalse);
    expect(await repo.get(name), 'Wendelin');
    expect(await repo.get(days), 7);
    expect(await repo.get(rate), 1.25);
    expect(await repo.get(rules), {
      'default': 'claude',
      'rules': [
        {'if': 'tee', 'then': 'phala'},
      ],
    });

    await repo.set(name, 'Wendy');
    expect(await repo.get(name), 'Wendy');
    await repo.remove(wake);
    expect(await repo.get(wake), isTrue);
  });

  test('decimal akzeptiert ganze Zahlen', () async {
    await repo.set(SettingKey.integer('x'), 2);
    expect(await repo.get(SettingKey.decimal('x')), 2.0);
  });

  test('eigene Kodierung', () async {
    expect(await repo.get(_mode), _Mode.voice);
    await repo.set(_mode, _Mode.text);
    expect(await repo.get(_mode), _Mode.text);
    expect(_mode.toString(), contains('ui.mode'));
  });

  test('falscher Typ wirft FormatException', () async {
    await repo.set(SettingKey.string('x'), 'text');
    await expectLater(repo.get(SettingKey.integer('x')), throwsFormatException);
    await expectLater(repo.get(SettingKey.json('x')), throwsFormatException);
  });
}
