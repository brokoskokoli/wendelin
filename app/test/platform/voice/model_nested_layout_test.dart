// Plattformabhängig (Dateisystem), siehe app/dart_test.yaml.
@Tags(['platform-sensitive'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wendelin/platform/voice/file_model_store.dart';
import 'package:wendelin/platform/voice/model_installer.dart';
import 'package:wendelin/platform/voice/nemo_sherpa.dart';
import 'package:wendelin/platform/voice/sherpa_voice_files.dart';
import 'package:wendelin/platform/voice/tar_bz2.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'tar_support.dart';

/// WP136: the sherpa archives carry their own top folder named like the
/// archive, so the files end up in `<model dir>/<base>/<base>/`.
void main() {
  late Directory tmp;
  late ModelInstaller inst;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nested');
    final store = FileModelStore(Directory('${tmp.path}/models'));
    inst = ModelInstaller(
      store: store,
      downloader: ModelDownloader(
        client: MockClient.streaming(
          (_, _) async => http.StreamedResponse(const Stream.empty(), 404),
        ),
        store: store,
      ),
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  String baseOf(SpeechModel m) =>
      m.files.first.name.replaceFirst('.tar.bz2', '');

  /// Unpacks a real `.tar.bz2` with [names] below the top folder [top]
  /// exactly like the installer does.
  void unpack(SpeechModel m, List<String> names, {String? top}) {
    final base = baseOf(m);
    final root = top ?? base;
    final archive = File('${tmp.path}/$base.tar.bz2')
      ..writeAsBytesSync(
        bz2(
          tar([
            tarEntry('$root/', [], type: '5'),
            for (final n in names)
              if (n.endsWith('/'))
                tarEntry('$root/$n', [], type: '5')
              else
                tarEntry('$root/$n', [1]),
          ]),
        ),
      );
    unpackTarBz2(archive.path, inst.unpackedDir(m, m.files.first).path, null);
  }

  String modelDir(SpeechModel m) => inst.store.modelDir(m.id).path;

  for (final (model, names) in [
    (
      SpeechModelCatalog.parakeetV3,
      [
        'encoder.int8.onnx',
        'decoder.int8.onnx',
        'joiner.int8.onnx',
        'tokens.txt',
      ],
    ),
    (
      SpeechModelCatalog.canary180m,
      ['encoder.int8.onnx', 'decoder.int8.onnx', 'tokens.txt'],
    ),
  ]) {
    group(model.id, () {
      test('Archiv mit oberstem Ordner: installiert und ladbar', () async {
        unpack(model, names);
        expect(
          File(
            '${modelDir(model)}/${baseOf(model)}/${baseOf(model)}/tokens.txt',
          ).existsSync(),
          isTrue,
          reason: 'Fixture hat die Struktur des echten Archivs',
        );
        expect(NemoFiles.find(model, modelDir(model)), isNotNull);
        expect(await inst.isInstalled(model), isTrue);
        expect(await inst.isDamaged(model), isFalse);
      });

      test('flache Struktur bleibt ladbar', () async {
        final base = Directory('${modelDir(model)}/${baseOf(model)}')
          ..createSync(recursive: true);
        for (final n in names) {
          File('${base.path}/$n').writeAsStringSync('x');
        }
        expect(NemoFiles.find(model, modelDir(model)), isNotNull);
        expect(await inst.isInstalled(model), isTrue);
      });

      test(
        'Ordner ohne Modelldateien: nicht installiert, beschädigt',
        () async {
          unpack(model, ['README.md']);
          expect(NemoFiles.find(model, modelDir(model)), isNull);
          expect(await inst.isInstalled(model), isFalse);
          expect(await inst.isDamaged(model), isTrue);
        },
      );
    });
  }

  test('nichts entpackt: nicht installiert und nicht beschädigt', () async {
    const m = SpeechModelCatalog.parakeetV3;
    expect(await inst.isInstalled(m), isFalse);
    expect(await inst.isDamaged(m), isFalse);
  });

  group('Piper und Kokoro', () {
    const piper = SpeechModelCatalog.voiceDe;
    const kokoro = SpeechModelCatalog.voiceKokoro;
    const files = ['x.onnx', 'tokens.txt', 'espeak-ng-data/'];

    test('Piper mit oberstem Ordner ist installiert', () async {
      unpack(piper, files);
      expect(
        PiperVoiceFiles.find(inst.unpackedDir(piper, piper.files.first)),
        isNotNull,
      );
      expect(await inst.isInstalled(piper), isTrue);
    });

    test('Piper-Ordner ohne tokens.txt: beschädigt', () async {
      unpack(piper, ['x.onnx', 'espeak-ng-data/']);
      expect(await inst.isInstalled(piper), isFalse);
      expect(await inst.isDamaged(piper), isTrue);
    });

    test('Kokoro braucht voices.bin', () async {
      unpack(kokoro, files);
      expect(await inst.isInstalled(kokoro), isFalse);
      unpack(kokoro, [...files, 'voices.bin']);
      expect(await inst.isInstalled(kokoro), isTrue);
    });
  });
}
