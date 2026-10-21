// Plattformabhängig (Dateisystem), siehe app/dart_test.yaml.
@Tags(['platform-sensitive'])
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart' show BZip2Decoder, InputFileStream;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:wendelin/platform/voice/disk_space.dart';
import 'package:wendelin/platform/voice/file_model_store.dart';
import 'package:wendelin/platform/voice/model_installer.dart';
import 'package:wendelin/platform/voice/tar_bz2.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'tar_support.dart';

/// Free space: roomy at the first query (download check), [later] after.
final class _SeqDisk implements DiskSpace {
  _SeqDisk(this.later);
  final int later;
  var _n = 0;
  @override
  Future<int?> freeBytes(String path) async => _n++ == 0 ? 1 << 40 : later;
}

Matcher _rejected(String reason) =>
    throwsA(isA<ArchiveRejected>().having((e) => e.reason, 'reason', reason));

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('unpack'));
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  File write(String name, List<int> bytes) =>
      File('${tmp.path}/$name')..writeAsBytesSync(bytes);

  group('Entpacken streamend (WP115)', () {
    test('großer Eintrag wird in kleinen Stücken geschrieben', () {
      const size = 24 << 20;
      const chunk = 256 << 10;
      final archive = write(
        'big.tar.bz2',
        bz2(
          tar([
            tarEntry('m/', [], type: '5'),
            tarEntry('m/model.onnx', Uint8List(size)),
            tarEntry('m/tokens.txt', [1, 2, 3]),
          ]),
        ),
      );
      final chunks = <int>[];
      final bytes = unpackTarBz2(
        archive.path,
        '${tmp.path}/out',
        64 << 20,
        chunkBytes: chunk,
        onChunk: chunks.add,
      );
      expect(bytes, size + 3);
      expect(File('${tmp.path}/out/m/model.onnx').lengthSync(), size);
      expect(chunks.reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(chunk));
      expect(chunks.length, greaterThanOrEqualTo(size ~/ chunk));
    });

    test('läuft auf dem vorwärts gelesenen, lazy dekodierten Strom '
        '(kein Tar im Speicher)', () {
      // decodeLazy hält nur ein Fenster; ein Zugriff zurück würfe.
      final archive = write(
        'w.tar.bz2',
        bz2(tar([tarEntry('a', Uint8List(24 << 20))])),
      );
      final input = InputFileStream(archive.path);
      addTearDown(input.closeSync);
      final lazy = BZip2Decoder().decodeLazy(input);
      var total = 0;
      walkTar(
        lazy,
        maxBytes: 64 << 20,
        chunkBytes: 1 << 20,
        onEntry: (path, dir, body) {
          for (var p = body.next(); p != null; p = body.next()) {
            total += p.length;
          }
        },
      );
      expect(total, 24 << 20);
      expect(lazy.position, greaterThan(24 << 20));
    });

    test('liest das Archiv beim Entpacken vorwärts, nicht vorab ganz', () {
      // Schwer komprimierbare Daten: das Archiv ist groß, der erste Block
      // klein dagegen.
      final rnd = Random(7);
      final data = Uint8List.fromList(
        List.generate(6 << 20, (_) => rnd.nextInt(256)),
      );
      final archive = write('s.tar.bz2', bz2(tar([tarEntry('a', data)])));
      final size = archive.lengthSync();
      final positions = <int>[];
      unpackTarBz2(
        archive.path,
        '${tmp.path}/s',
        64 << 20,
        chunkBytes: 256 << 10,
        onInput: positions.add,
      );
      expect(size, greaterThan(5 << 20));
      expect(positions.first, lessThan(size ~/ 4));
      expect(positions.last, greaterThan(size ~/ 2));
    });

    test('Bitfehler in der bzip2-Prüfsumme: beschädigt, nichts bleibt', () {
      final bytes = bz2(tar([tarEntry('a', Uint8List(1 << 16))]));
      // Offset 10: CRC des ersten Blocks; die Daten selbst bleiben lesbar.
      bytes[10] ^= 0x01;
      final archive = write('x.tar.bz2', bytes);
      expect(
        () => unpackTarBz2(archive.path, '${tmp.path}/x', null),
        _rejected('corrupt'),
      );
      expect(Directory('${tmp.path}/x').existsSync(), isFalse);
      expect(Directory('${tmp.path}/x.tmp').existsSync(), isFalse);
    });

    test('Größenlimit: zu viel entpackt wird abgelehnt, nichts bleibt', () {
      final archive = write(
        'l.tar.bz2',
        bz2(tar([tarEntry('big', Uint8List(4 << 20))])),
      );
      expect(
        () => unpackTarBz2(archive.path, '${tmp.path}/l', 1 << 20),
        _rejected('too-large'),
      );
      expect(Directory('${tmp.path}/l').existsSync(), isFalse);
      expect(Directory('${tmp.path}/l.tmp').existsSync(), isFalse);
      // Exakt am Limit geht (Header 512 + Körper + Padding).
      expect(
        unpackTarBz2(archive.path, '${tmp.path}/ok', (4 << 20) + 512),
        4 << 20,
      );
    });

    test('Pfad-Ausbruch im Archiv: abgelehnt, Ziel unberührt', () {
      for (final bad in ['../evil', 'a/../../evil', '/etc/evil']) {
        final archive = write(
          'p.tar.bz2',
          bz2(
            tar([
              tarEntry(bad, [1]),
            ]),
          ),
        );
        expect(
          () => unpackTarBz2(archive.path, '${tmp.path}/p', null),
          _rejected('unsafe-path'),
          reason: bad,
        );
        expect(Directory('${tmp.path}/p').existsSync(), isFalse);
        expect(File('${tmp.path}/evil').existsSync(), isFalse);
      }
    });

    test('Symlink-Eintrag: abgelehnt', () {
      final archive = write(
        's.tar.bz2',
        bz2(tar([tarEntry('l', [], type: '2', link: '/etc/passwd')])),
      );
      expect(
        () => unpackTarBz2(archive.path, '${tmp.path}/s', null),
        _rejected('forbidden-entry'),
      );
    });

    test('abgeschnittenes bzip2 und lügende Größe: beschädigt', () {
      final full = bz2(tar([tarEntry('a', Uint8List(3 << 20))]));
      final cut = write('c.tar.bz2', full.sublist(0, full.length ~/ 2));
      expect(
        () => unpackTarBz2(cut.path, '${tmp.path}/c', null),
        _rejected('corrupt'),
      );
      expect(Directory('${tmp.path}/c.tmp').existsSync(), isFalse);
    });
  });

  group('ModelInstaller entpackt (WP115)', () {
    SpeechModel model(Uint8List archive) => SpeechModel(
      id: 'tts-u',
      kind: SpeechModelKind.tts,
      displayName: 'U',
      languages: const {'de'},
      license: 'x',
      source: 'x',
      files: [
        ModelFile(
          name: 'u.tar.bz2',
          url: 'https://example.org/u.tar.bz2',
          sizeBytes: archive.length,
          sha256: 'x',
          archive: ModelArchive.tarBz2,
        ),
      ],
    );

    ModelInstaller installer(int free) {
      final store = FileModelStore(Directory('${tmp.path}/models'));
      return ModelInstaller(
        store: store,
        downloader: ModelDownloader(
          client: http_testing.MockClient((_) async => http.Response('', 404)),
          store: store,
        ),
        disk: _SeqDisk(free),
      );
    }

    Future<List<String>> capture(Future<void> Function() run) async {
      final lines = <String>[];
      final saved = voiceLogSink;
      voiceLogSink = lines.add;
      try {
        await run();
      } finally {
        voiceLogSink = saved;
      }
      return lines;
    }

    test('zu wenig Platz vor dem Entpacken: klare Meldung, Archiv bleibt, '
        'Logzeile mit Größen', () async {
      final bytes = bz2(
        tar([
          tarEntry('a', [1]),
        ]),
      );
      final m = model(bytes);
      final inst = installer(1000);
      inst.store.root.createSync(recursive: true);
      inst.store.modelDir(m.id).createSync(recursive: true);
      File(inst.store.pathOf(m.id, 'u.tar.bz2')).writeAsBytesSync(bytes);
      Object? error;
      final lines = await capture(() async {
        try {
          await inst.install(m);
        } on InsufficientSpaceException catch (e) {
          error = e;
        }
      });
      expect(error, isA<InsufficientSpaceException>());
      expect(
        lines.any(
          (l) =>
              l.contains('model-unpack-failed') &&
              l.contains('reason=no-space') &&
              l.contains('free_bytes=1000') &&
              l.contains('archive_bytes=${bytes.length}'),
        ),
        isTrue,
        reason: lines.join('\n'),
      );
      expect(File(inst.store.pathOf(m.id, 'u.tar.bz2')).existsSync(), isTrue);
    });

    test(
      'abgelehntes Archiv: Logzeile mit Grund und Größen, ohne Pfad',
      () async {
        final bytes = bz2(
          tar([
            tarEntry('../x', [1]),
          ]),
        );
        final m = model(bytes);
        final inst = installer(1 << 40);
        inst.store.modelDir(m.id).createSync(recursive: true);
        File(inst.store.pathOf(m.id, 'u.tar.bz2')).writeAsBytesSync(bytes);
        final lines = await capture(() async {
          await expectLater(inst.install(m), throwsA(isA<ArchiveRejected>()));
        });
        final failed = lines.singleWhere((l) => l.contains('unpack-failed'));
        expect(failed, contains('reason=unsafe-path'));
        expect(failed, contains('archive_bytes=${bytes.length}'));
        expect(failed, isNot(contains('..')));
        expect(
          File(inst.store.pathOf(m.id, 'u.tar.bz2')).existsSync(),
          isFalse,
        );
      },
    );

    test(
      'Konflikt Datei/Ordner im Archiv (a und a/b): corrupt, Archiv gelöscht',
      () async {
        final bytes = bz2(
          tar([
            tarEntry('a', [1]),
            tarEntry('a/b', [2]),
          ]),
        );
        final m = model(bytes);
        final inst = installer(1 << 40);
        inst.store.modelDir(m.id).createSync(recursive: true);
        File(inst.store.pathOf(m.id, 'u.tar.bz2')).writeAsBytesSync(bytes);
        final lines = await capture(() async {
          await expectLater(
            inst.install(m),
            throwsA(
              isA<ArchiveRejected>().having((e) => e.reason, 'r', 'corrupt'),
            ),
          );
        });
        expect(lines.any((l) => l.contains('reason=corrupt')), isTrue);
        expect(
          File(inst.store.pathOf(m.id, 'u.tar.bz2')).existsSync(),
          isFalse,
        );
      },
    );

    test(
      'Schreibfehler (io, Ordner schreibgeschützt): Archiv bleibt',
      () async {
        final bytes = bz2(
          tar([
            tarEntry('a', [1]),
          ]),
        );
        final m = model(bytes);
        final inst = installer(1 << 40);
        final dir = inst.store.modelDir(m.id)..createSync(recursive: true);
        File(inst.store.pathOf(m.id, 'u.tar.bz2')).writeAsBytesSync(bytes);
        Process.runSync('chmod', ['555', dir.path]);
        addTearDown(() => Process.runSync('chmod', ['755', dir.path]));
        final lines = await capture(() async {
          await expectLater(
            inst.install(m),
            throwsA(isA<ArchiveRejected>().having((e) => e.reason, 'r', 'io')),
          );
        });
        expect(lines.any((l) => l.contains('reason=io')), isTrue);
        expect(File(inst.store.pathOf(m.id, 'u.tar.bz2')).existsSync(), isTrue);
      },
    );

    test('Erfolg: Logzeilen model-unpack und model-unpacked', () async {
      final bytes = bz2(
        tar([
          tarEntry('a', [1, 2, 3]),
        ]),
      );
      final m = model(bytes);
      final inst = installer(1 << 40);
      inst.store.modelDir(m.id).createSync(recursive: true);
      File(inst.store.pathOf(m.id, 'u.tar.bz2')).writeAsBytesSync(bytes);
      final lines = await capture(() => inst.install(m));
      expect(lines.any((l) => l.contains('model-unpack ')), isTrue);
      expect(
        lines.any((l) => l.contains('model-unpacked') && l.contains('bytes=3')),
        isTrue,
      );
    });
  });
}
