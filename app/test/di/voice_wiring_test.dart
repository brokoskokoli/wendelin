import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/core_providers.dart';
import 'package:wendelin/di/home_assistant.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/platform/voice/sherpa_tts.dart';
import 'package:wendelin/platform/voice/whisper_stt.dart';
import 'package:wendelin_storage/testing.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  test('Ladeplan: die App-Sprache geht als Rückfall an den Erkenner', () async {
    String? seen;
    final c = ProviderContainer(
      overrides: [
        startupProvider.overrideWithValue(
          const StartupSettings(language: 'fr'),
        ),
        haStoreProvider.overrideWithValue(SecretStoreHa(InMemorySecretStore())),
        sttBackendStarterProvider.overrideWithValue((
          model,
          dir, {
          hintTerms = const [],
          hotwordsScore = 1.5,
          fallbackLanguage = 'de',
        }) async {
          seen = fallbackLanguage;
          return _NoBackend();
        }),
      ],
    );
    addTearDown(c.dispose);
    await c.read(whisperLoaderProvider)(SpeechModelCatalog.canary180m, '/x');
    expect(seen, 'fr');
  });

  test(
    'Ausgefallener HA-Speicher: Hinweisbegriffe ohne HA, Erkennung lädt',
    () async {
      List<String>? terms;
      final c = ProviderContainer(
        overrides: [
          haStoreProvider.overrideWithValue(SecretStoreHa(_ThrowingSecrets())),
          sttBackendStarterProvider.overrideWithValue((
            model,
            dir, {
            hintTerms = const [],
            hotwordsScore = 1.5,
            fallbackLanguage = 'de',
          }) async {
            terms = hintTerms;
            return _NoBackend();
          }),
        ],
      );
      addTearDown(c.dispose);
      await c.read(whisperLoaderProvider)(SpeechModelCatalog.parakeetV3, '/x');
      expect(terms, contains('Wendelin'));
    },
  );

  group('installedSherpaVoices', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('voices'));
    tearDown(() => root.deleteSync(recursive: true));

    Future<List<SherpaVoice>> voices({required bool voicesBin}) {
      final model = SpeechModelCatalog.voiceKokoro;
      final base = model.files.first.name.replaceFirst(
        RegExp(r'\.tar\.bz2$'),
        '',
      );
      final d = Directory('${root.path}/$base')..createSync(recursive: true);
      File('${d.path}/model.onnx').writeAsStringSync('x');
      File('${d.path}/tokens.txt').writeAsStringSync('x');
      Directory('${d.path}/espeak-ng-data').createSync();
      if (voicesBin) File('${d.path}/voices.bin').writeAsStringSync('x');
      final service = _DirService(root)..installed.add(model.id);
      return installedSherpaVoices(service, SpeechModelCatalog.standard);
    }

    test(
      'Kokoro mit voices.bin: gelistet; ohne: nie als Piper geladen',
      () async {
        expect(
          (await voices(voicesBin: true)).map((v) => v.files.voicesBin),
          everyElement(isNotNull),
        );
        root.listSync().whereType<Directory>().forEach(
          (d) => File('${d.path}/voices.bin').deleteSync(),
        );
        expect(await voices(voicesBin: false), isEmpty);
      },
    );
  });
}

final class _DirService implements SpeechModelService {
  _DirService(this.root);
  final Directory root;
  final installed = <String>{};
  @override
  Future<bool> isInstalled(SpeechModel model) async =>
      installed.contains(model.id);
  @override
  Directory directoryOf(SpeechModel model) => root;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ThrowingSecrets implements SecretStore {
  @override
  Future<String?> read(String key) async => throw TypeError();
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<void> delete(String key) async {}
  @override
  Future<Set<String>> listKeys() async => {};
}

final class _NoBackend implements WhisperBackend {
  @override
  Future<WhisperResult> transcribe(Float32List samples, {String? language}) =>
      throw UnimplementedError();
  @override
  Future<void> dispose() async {}
}
