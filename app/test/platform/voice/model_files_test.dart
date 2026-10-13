// Plattformabhängig (FFI bzw. Dateisystem), siehe app/dart_test.yaml.
@Tags(['platform-sensitive'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show BZip2Encoder;
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wendelin/platform/voice/disk_space.dart';
import 'package:wendelin/platform/voice/file_model_store.dart';
import 'package:wendelin/platform/voice/model_installer.dart';
import 'package:wendelin/platform/voice/tar_bz2.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// One tar header + body (GNU/ustar, checksum filled in).
List<int> tarEntry(
  String name,
  List<int> data, {
  String type = '0',
  String link = '',
  String prefix = '',
}) {
  final h = Uint8List(512);
  void put(int at, String s) => h.setRange(at, at + s.length, utf8.encode(s));
  put(0, name);
  put(100, '0000644');
  put(124, data.length.toRadixString(8).padLeft(11, '0'));
  put(136, '00000000000');
  put(148, '        ');
  put(156, type);
  put(157, link);
  put(257, 'ustar');
  put(263, '00');
  put(345, prefix);
  final sum = h.fold(0, (a, b) => a + b);
  put(148, '${sum.toRadixString(8).padLeft(6, '0')}\x00 ');
  final pad = (512 - data.length % 512) % 512;
  return [...h, ...data, ...List.filled(pad, 0)];
}

Uint8List tar(List<List<int>> entries) => Uint8List.fromList([
  for (final e in entries) ...e,
  ...List.filled(1024, 0),
]);

Uint8List bz2(List<int> bytes) =>
    Uint8List.fromList(BZip2Encoder().encodeBytes(bytes));

final class FixedDisk implements DiskSpace {
  FixedDisk(this.free);
  int? free;
  @override
  Future<int?> freeBytes(String path) async => free;
}

Matcher _rejected(String part) => throwsA(
  isA<ArchiveRejected>().having((e) => e.message, 'message', contains(part)),
);

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('models'));
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  modelStoreContract(
    () async => FileModelStore(
      Directory('${(await Directory.systemTemp.createTemp('store')).path}/m'),
    ),
    name: 'FileModelStore',
  );

  group('FileModelStore', () {
    test('Teil-Download liegt als .part neben der Datei', () async {
      final s = FileModelStore(tmp);
      await s.append('whisper-base', 'a.onnx', [1, 2]);
      expect(File('${tmp.path}/whisper-base/a.onnx.part').existsSync(), isTrue);
      expect(await s.hasPartial(SpeechModelCatalog.whisperBase), isFalse);
      await s.commit('whisper-base', 'a.onnx');
      expect(File(s.pathOf('whisper-base', 'a.onnx')).readAsBytesSync(), [
        1,
        2,
      ]);
      await s.deleteFile('whisper-base', 'a.onnx');
      await s.deleteFile('whisper-base', 'a.onnx');
      expect(await s.exists('whisper-base', 'a.onnx'), isFalse);
    });

    test('Namen mit Pfadanteilen werden abgelehnt', () {
      final s = FileModelStore(tmp);
      for (final bad in ['../x', 'a/b', '.hidden', '..', '', 'a\\b']) {
        expect(() => s.pathOf('m', bad), throwsArgumentError, reason: bad);
        expect(() => s.modelDir(bad), throwsArgumentError, reason: bad);
      }
      expect(
        s.pathOf('silero-vad', 'silero_vad.onnx'),
        endsWith('silero-vad/silero_vad.onnx'),
      );
    });

    test('hasPartial erkennt angefangene Downloads', () async {
      final s = FileModelStore(tmp);
      await s.append('silero-vad', 'silero_vad.onnx', [1]);
      expect(await s.hasPartial(SpeechModelCatalog.sileroVad), isTrue);
    });
  });

  group('readTar / extractTarBz2', () {
    test('Dateien, Ordner, GNU-Langname, PAX-Pfad, ustar-Präfix', () {
      final long = '${'a' * 120}/f.txt';
      final entries = readTar(
        tar([
          tarEntry('voice/', [], type: '5'),
          tarEntry('voice/tokens.txt', utf8.encode('t')),
          tarEntry('././@LongLink', utf8.encode('$long\x00'), type: 'L'),
          tarEntry('ignored', utf8.encode('long')),
          tarEntry(
            'PaxHeader',
            utf8.encode('27 path=voice/pax-name.txt\n'),
            type: 'x',
          ),
          tarEntry('short', utf8.encode('pax')),
          tarEntry('g', utf8.encode('10 a=b\n'), type: 'g'),
          tarEntry('x.onnx', utf8.encode('m'), prefix: 'voice/deep'),
          tarEntry('./voice//dot.txt', [], type: '\x00'),
        ]),
      );
      expect(entries.map((e) => e.path), [
        'voice',
        'voice/tokens.txt',
        long,
        'voice/pax-name.txt',
        'voice/deep/x.onnx',
        'voice/dot.txt',
      ]);
      expect(entries.first.directory, isTrue);
      expect(utf8.decode(entries[2].data), 'long');
    });

    for (final (name, entry, message) in [
      (
        'Symlink',
        tarEntry('voice/l', [], type: '2', link: '/etc/passwd'),
        'nicht erlaubten',
      ),
      (
        'Hardlink',
        tarEntry('voice/h', [], type: '1', link: 'voice/x'),
        'nicht erlaubten',
      ),
      ('Gerät', tarEntry('voice/dev', [], type: '3'), 'nicht erlaubten'),
      ('absoluter Pfad', tarEntry('/etc/x', [1]), 'Unsicherer Pfad'),
      ('..', tarEntry('voice/../../x', [1]), 'Unsicherer Pfad'),
      ('nur Punkte', tarEntry('./', [], type: '5'), 'Unsicherer Pfad'),
    ]) {
      test('lehnt $name ab', () {
        expect(
          () => readTar(
            tar([
              tarEntry('ok', [1]),
              entry,
            ]),
          ),
          _rejected(message),
        );
      });
    }

    test('beschädigte Header', () {
      final t = tar([
        tarEntry('a', [1, 2, 3]),
      ]);
      final badSum = Uint8List.fromList(t)..[0] = 0x62;
      expect(() => readTar(badSum), _rejected('Prüfsumme'));
      final truncated = Uint8List.sublistView(t, 0, 512 + 512);
      final big = Uint8List.fromList(
        tarEntry('a', List.filled(2000, 1)).sublist(0, 1024),
      );
      expect(readTar(truncated).single.data, [1, 2, 3]);
      expect(() => readTar(big), _rejected('beschädigt'));
    });

    test('entpackt atomar, ersetzt Ziel erst nach Erfolg', () async {
      final archive = File('${tmp.path}/v.tar.bz2')
        ..writeAsBytesSync(
          bz2(
            tar([
              tarEntry('voice/', [], type: '5'),
              tarEntry('voice/tokens.txt', utf8.encode('t')),
              tarEntry('voice/espeak-ng-data/de_dict', [1, 2]),
            ]),
          ),
        );
      final target = Directory('${tmp.path}/out')..createSync();
      File('${target.path}/alt.txt').writeAsStringSync('alt');
      await extractTarBz2(archive, target);
      expect(File('${target.path}/voice/tokens.txt').readAsStringSync(), 't');
      expect(
        File('${target.path}/voice/espeak-ng-data/de_dict').lengthSync(),
        2,
      );
      expect(File('${target.path}/alt.txt').existsSync(), isFalse);
      expect(Directory('${target.path}.tmp').existsSync(), isFalse);
      expect(archive.existsSync(), isTrue); // caller deletes it

      final evil = File('${tmp.path}/e.tar.bz2')
        ..writeAsBytesSync(
          bz2(
            tar([
              tarEntry('voice/ok', [1]),
              tarEntry('voice/l', [], type: '2', link: '../../x'),
            ]),
          ),
        );
      await expectLater(
        extractTarBz2(evil, target),
        throwsA(isA<ArchiveRejected>()),
      );
      expect(File('${target.path}/voice/tokens.txt').existsSync(), isTrue);
      expect(File('${target.path}/voice/ok').existsSync(), isFalse);
    });

    test('Schreibfehler (Datei, wo ein Ordner hin muss): abgelehnt, '
        'nichts bleibt liegen', () async {
      final clash = File('${tmp.path}/c.tar.bz2')
        ..writeAsBytesSync(
          bz2(
            tar([
              tarEntry('voice/a', [1]),
              tarEntry('voice/a/b', [2]),
            ]),
          ),
        );
      final target = Directory('${tmp.path}/c');
      await expectLater(
        extractTarBz2(clash, target),
        _rejected('ließ sich nicht entpacken'),
      );
      expect(target.existsSync(), isFalse);
      expect(Directory('${target.path}.tmp').existsSync(), isFalse);
    });

    test('bzip2-Bombe und kaputtes bzip2 werden abgelehnt', () async {
      final bomb = File('${tmp.path}/b.tar.bz2')
        ..writeAsBytesSync(bz2(tar([tarEntry('big', Uint8List(4 << 20))])));
      await expectLater(
        extractTarBz2(
          bomb,
          Directory('${tmp.path}/b'),
          maxUnpackedBytes: 1 << 20,
        ),
        _rejected('zu groß'),
      );
      final broken = File('${tmp.path}/k.tar.bz2')
        ..writeAsBytesSync([
          ...bz2(
            tar([
              tarEntry('a', [1]),
            ]),
          ).sublist(0, 20),
          1,
          2,
          3,
        ]);
      await expectLater(
        extractTarBz2(broken, Directory('${tmp.path}/k')),
        throwsA(isA<ArchiveRejected>()),
      );
      expect(Directory('${tmp.path}/b').existsSync(), isFalse);
    });
  });

  test('StatvfsDiskSpace liefert auf dem Host freien Platz', () async {
    final free = await const StatvfsDiskSpace().freeBytes(tmp.path);
    if (Platform.isMacOS || Platform.isLinux) {
      expect(free, greaterThan(1 << 20));
      final df = Process.runSync('df', ['-k', tmp.path]);
      final kb = int.parse(
        (df.stdout as String).trim().split('\n').last.split(RegExp(r'\s+'))[3],
      );
      // Same order of magnitude as df (values change while tests run).
      expect(free! / 1024, closeTo(kb, kb * 0.2 + 1024 * 1024));
    }
    expect(await const StatvfsDiskSpace().freeBytes('/gibt/es/nicht'), isNull);
    expect(requiredSpace(100, archive: false), 100 + (50 << 20));
    expect(requiredSpace(100, archive: true), 400 + (50 << 20));
  });

  group('ModelInstaller', () {
    final voiceTar = bz2(
      tar([
        tarEntry('vits-x/', [], type: '5'),
        tarEntry('vits-x/x.onnx', [1]),
        tarEntry('vits-x/tokens.txt', [2]),
        tarEntry('vits-x/espeak-ng-data/', [], type: '5'),
      ]),
    );
    final small = utf8.encode('model-bytes');
    SpeechModel voiceModel(List<int> bytes) => SpeechModel(
      id: 'tts-test',
      kind: SpeechModelKind.tts,
      displayName: 'Test',
      languages: const {'de'},
      license: 'x',
      source: 'x',
      files: [
        ModelFile(
          name: 'vits-x.tar.bz2',
          url: 'https://example.org/vits-x.tar.bz2',
          sizeBytes: bytes.length,
          sha256: sha256.convert(bytes).toString(),
          archive: ModelArchive.tarBz2,
        ),
      ],
    );
    final plain = SpeechModel(
      id: 'vad-test',
      kind: SpeechModelKind.vad,
      displayName: 'VAD',
      languages: const {},
      license: 'x',
      source: 'x',
      files: [
        ModelFile(
          name: 'v.onnx',
          url: 'https://example.org/v.onnx',
          sizeBytes: small.length,
          sha256: sha256.convert(small).toString(),
        ),
      ],
    );

    (ModelInstaller, List<Uri>) installer(
      Map<String, List<int>> files, {
      int? free,
    }) {
      final requests = <Uri>[];
      final client = MockClient.streaming((req, _) async {
        requests.add(req.url);
        final body = files[req.url.pathSegments.last];
        if (body == null) {
          return http.StreamedResponse(const Stream.empty(), 404);
        }
        return http.StreamedResponse(
          Stream.value(body),
          200,
          contentLength: body.length,
        );
      });
      final store = FileModelStore(Directory('${tmp.path}/models'));
      return (
        ModelInstaller(
          store: store,
          downloader: ModelDownloader(client: client, store: store),
          disk: FixedDisk(free ?? (1 << 40)),
        ),
        requests,
      );
    }

    test(
      'lädt, entpackt, löscht das Archiv; zweiter Lauf lädt nichts',
      () async {
        final (inst, requests) = installer({'vits-x.tar.bz2': voiceTar});
        final model = voiceModel(voiceTar);
        expect(await inst.isInstalled(model), isFalse);
        expect(await inst.remainingBytes(model), voiceTar.length);
        var unpacking = 0;
        final progress = <double>[];
        await inst.install(
          model,
          onProgress: (p) => progress.add(p.fraction),
          onUnpacking: () => unpacking++,
        );
        expect(unpacking, 1);
        expect(progress.last, 1.0);
        expect(await inst.isInstalled(model), isTrue);
        final dir = inst.unpackedDir(model, model.files.single);
        expect(File('${dir.path}/vits-x/tokens.txt').existsSync(), isTrue);
        expect(
          File(inst.store.pathOf(model.id, 'vits-x.tar.bz2')).existsSync(),
          isFalse,
        );
        expect(await inst.remainingBytes(model), 0);
        await inst.install(model);
        expect(requests, hasLength(1));
        await inst.delete(model);
        expect(await inst.isInstalled(model), isFalse);
      },
    );

    test(
      'abgeschnittene Datei gilt als fehlend und wird neu geladen',
      () async {
        final (inst, requests) = installer({'v.onnx': small});
        await inst.install(plain);
        expect(await inst.isInstalled(plain), isTrue);
        final file = File(inst.store.pathOf(plain.id, 'v.onnx'))
          ..writeAsBytesSync(small.sublist(0, 5));
        expect(await inst.isInstalled(plain), isFalse);
        expect(await inst.remainingBytes(plain), small.length);
        await inst.install(plain);
        expect(file.readAsBytesSync(), small);
        expect(await inst.isInstalled(plain), isTrue);
        expect(requests, hasLength(2));
      },
    );

    test('heruntergeladenes, zu kurzes Archiv wird neu geladen', () async {
      final (inst, requests) = installer({'vits-x.tar.bz2': voiceTar});
      final model = voiceModel(voiceTar);
      final archive = File(inst.store.pathOf(model.id, 'vits-x.tar.bz2'))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(voiceTar.sublist(0, 10));
      await inst.install(model);
      expect(requests, hasLength(1));
      expect(await inst.isInstalled(model), isTrue);
      expect(archive.existsSync(), isFalse);
    });

    test('zu wenig Platz: Fehler vor dem Download', () async {
      final (inst, requests) = installer({'v.onnx': small}, free: 10 << 20);
      await expectLater(
        inst.install(plain),
        throwsA(
          isA<InsufficientSpaceException>().having(
            (e) => e.message,
            'message',
            contains('MB nötig'),
          ),
        ),
      );
      expect(requests, isEmpty);
      const e = InsufficientSpaceException(
        requiredBytes: 2500000,
        freeBytes: 1000000,
      );
      expect(e.message, 'Zu wenig Speicherplatz: 3 MB nötig, 1 MB frei.');
      expect(e.toString(), contains('3 MB'));
    });

    test('unbekannter Platz: Download läuft trotzdem', () async {
      final (inst, _) = installer({'v.onnx': small});
      (inst.disk as FixedDisk).free = null;
      await inst.install(plain);
      expect(await inst.isInstalled(plain), isTrue);
    });

    test('Archiv mit Symlink: abgelehnt und verworfen', () async {
      final evil = bz2(tar([tarEntry('vits-x/l', [], type: '2', link: '/')]));
      final (inst, _) = installer({'vits-x.tar.bz2': evil});
      final model = voiceModel(evil);
      await expectLater(inst.install(model), throwsA(isA<ArchiveRejected>()));
      expect(await inst.isInstalled(model), isFalse);
      expect(await inst.store.exists(model.id, 'vits-x.tar.bz2'), isFalse);
    });

    test('Prüfsumme falsch: ModelDownloadException(checksum)', () async {
      final (inst, _) = installer({'v.onnx': utf8.encode('model-bytez')});
      await expectLater(
        inst.install(plain),
        throwsA(
          isA<ModelDownloadException>().having(
            (e) => e.kind,
            'kind',
            DownloadErrorKind.checksum,
          ),
        ),
      );
      expect(await inst.isInstalled(plain), isFalse);
    });

    test('Abbruch vor dem Entpacken', () async {
      final (inst, _) = installer({'vits-x.tar.bz2': voiceTar});
      final model = voiceModel(voiceTar);
      final cancel = CancelToken();
      await expectLater(
        inst.install(
          model,
          cancel: cancel,
          onProgress: (p) {
            if (p.fraction == 1) cancel.cancel();
          },
        ),
        throwsA(
          anyOf(isA<CancelledException>(), isA<ModelDownloadException>()),
        ),
      );
      expect(await inst.isInstalled(model), isFalse);
      // Resumes: the archive is there, only unpacking is left.
      expect(await inst.remainingBytes(model), 0);
      await inst.install(model);
      expect(await inst.isInstalled(model), isTrue);
    });
  });
}
