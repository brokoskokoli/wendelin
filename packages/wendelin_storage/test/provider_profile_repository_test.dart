import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'support/storage_fixture.dart';

ProviderProfile _claude({String name = 'Claude API'}) => ProviderProfile(
  id: 'claude',
  name: name,
  type: ProviderType.anthropic,
  defaultModel: 'claude-haiku',
  privacy: PrivacyLevel.standard,
  authMethod: const ApiKeyAuth('provider.claude.apiKey'),
  budgetMonthly: 5000000,
  warnThreshold: 0.8,
  extraHeaders: const {'anthropic-beta': 'x'},
  options: const {
    'enableServerWebSearch': true,
    'thinkingBudget': 2000,
    'nested': {
      'list': [1, 'zwei', null],
    },
  },
);

ProviderProfile _ollama() => ProviderProfile(
  id: 'ollama',
  name: 'Ollama Homeserver',
  type: ProviderType.openaiCompatible,
  baseUrl: 'http://homeserver:11434/v1',
  defaultModel: 'qwen3',
  privacy: PrivacyLevel.local,
  authMethod: const NoAuth(),
);

void main() {
  late WendelinStorage storage;
  late ProviderProfileRepository repo;

  setUp(() {
    storage = openTestStorage().storage;
    repo = storage.providerProfiles;
  });
  tearDown(() => storage.close());

  test('save/get: Round-Trip inklusive options und ohne Secrets', () async {
    await repo.save(_claude());
    expect(await repo.get('claude'), _claude());
    expect(await repo.get('fehlt'), isNull);
  });

  test('save ersetzt bestehendes Profil, list in Einfügereihenfolge', () async {
    await repo.save(_claude());
    await repo.save(_ollama());
    await repo.save(_claude(name: 'Claude neu'));
    expect(await repo.list(), [_claude(name: 'Claude neu'), _ollama()]);
  });

  test('delete', () async {
    await repo.save(_ollama());
    expect(await repo.delete('ollama'), isTrue);
    expect(await repo.delete('ollama'), isFalse);
    expect(await repo.list(), isEmpty);
  });

  test('Default-Profil setzen, wechseln, beim Löschen entfernen', () async {
    expect(await repo.defaultProfile(), isNull);
    await repo.save(_claude());
    await repo.save(_ollama());
    await repo.setDefault('claude');
    expect(await repo.defaultProfile(), _claude());
    await repo.setDefault('ollama');
    expect(await repo.defaultProfile(), _ollama());
    await repo.delete('claude');
    expect(await repo.defaultProfile(), _ollama());
    await repo.delete('ollama');
    expect(await repo.defaultProfile(), isNull);
    await repo.save(_ollama());
    expect(await repo.defaultProfile(), isNull);
  });

  test('setDefault mit unbekanntem Profil wirft', () async {
    await expectLater(repo.setDefault('fehlt'), throwsArgumentError);
  });

  test(
    'Secret-artige Schlüssel in extraHeaders/options werden abgelehnt',
    () async {
      for (final p in [
        _ollama().copyWith(extraHeaders: {'Authorization': 'Bearer abc'}),
        _ollama().copyWith(extraHeaders: {'X-Api-Key': 'abc'}),
        _ollama().copyWith(options: {'apiKey': 'abc'}),
        _ollama().copyWith(
          options: {
            'mcp': [
              {'token': 'abc'},
            ],
          },
        ),
      ]) {
        await expectLater(repo.save(p), throwsArgumentError, reason: '$p');
      }
      expect(await repo.list(), isEmpty);
      await repo.save(_ollama().copyWith(options: {'maxTokens': 512}));
      expect((await repo.get('ollama'))!.options, {'maxTokens': 512});
    },
  );
}
