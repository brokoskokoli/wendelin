import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

final payload = utf8.encode('0123456789' * 100); // 1000 bytes
final payloadSha = sha256.convert(payload).toString();
final small = utf8.encode('tokens');

ModelFile file(String name, List<int> bytes, {String? sha}) => ModelFile(
  name: name,
  url: 'https://models.example/$name',
  sizeBytes: bytes.length,
  sha256: sha ?? sha256.convert(bytes).toString(),
);

SpeechModel model(List<ModelFile> files) => SpeechModel(
  id: 'm',
  kind: SpeechModelKind.stt,
  displayName: 'Test',
  languages: const {'de'},
  files: files,
  license: 'MIT',
  source: 'Test',
);

Matcher downloadError(DownloadErrorKind kind) =>
    throwsA(isA<ModelDownloadException>().having((e) => e.kind, 'kind', kind));

/// Server for [files]: honours `Range`, sends 100-byte chunks.
final class FakeServer {
  FakeServer(this.files, {this.ignoreRange = false});

  final Map<String, List<int>> files;
  final bool ignoreRange;
  final requests = <http.BaseRequest>[];

  /// Status to answer the next request with (then cleared).
  int? nextStatus;

  /// Stops sending after this many bytes and keeps the connection open.
  int? hangAfter;

  /// Fails the body with a network error after this many bytes.
  int? failAfter;

  late final client = MockClient.streaming((req, _) async {
    requests.add(req);
    final status = nextStatus;
    nextStatus = null;
    if (status != null) {
      return http.StreamedResponse(Stream.value([1, 2, 3]), status);
    }
    final name = req.url.pathSegments.last;
    final data = files[name]!;
    var start = 0;
    var code = 200;
    final range = req.headers['Range'];
    if (range != null && !ignoreRange) {
      start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      if (start >= data.length) {
        return http.StreamedResponse(const Stream.empty(), 416);
      }
      code = 206;
    }
    return http.StreamedResponse(
      _body(data.sublist(start)),
      code,
      contentLength: data.length - start,
    );
  });

  Stream<List<int>> _body(List<int> bytes) async* {
    for (var i = 0; i < bytes.length; i += 100) {
      if (hangAfter != null && i >= hangAfter!) {
        await Completer<void>().future; // never completes
      }
      if (failAfter != null && i >= failAfter!) {
        throw const SocketLikeException();
      }
      yield bytes.sublist(i, i + 100 > bytes.length ? bytes.length : i + 100);
    }
  }
}

final class SocketLikeException implements Exception {
  const SocketLikeException();
}

void main() {
  late FakeModelStore store;

  setUp(() => store = FakeModelStore());

  test(
    'lädt alle Dateien, prüft SHA-256, committet, meldet Fortschritt',
    () async {
      final server = FakeServer({'a.onnx': payload, 'tokens.txt': small});
      final m = model([file('a.onnx', payload), file('tokens.txt', small)]);
      final d = ModelDownloader(client: server.client, store: store);
      final progress = <DownloadProgress>[];
      expect(await d.isInstalled(m), isFalse);
      await d.download(m, onProgress: progress.add);
      expect(await d.isInstalled(m), isTrue);
      expect(store.finalBytes('m', 'a.onnx'), payload);
      expect(store.finalBytes('m', 'tokens.txt'), small);
      expect(progress.last.receivedBytes, m.sizeBytes);
      expect(progress.last.fraction, 1);
      expect(
        progress.map((p) => p.receivedBytes),
        orderedEquals(List.of(progress.map((p) => p.receivedBytes))..sort()),
      );
      expect(progress.first.toString(), contains('m'));
      expect(server.requests.every((r) => r.headers['Range'] == null), isTrue);
    },
  );

  test('vorhandene Dateien werden übersprungen', () async {
    store.seedFinal('m', 'a.onnx', payload);
    final server = FakeServer({'a.onnx': payload});
    final progress = <DownloadProgress>[];
    await ModelDownloader(
      client: server.client,
      store: store,
    ).download(model([file('a.onnx', payload)]), onProgress: progress.add);
    expect(server.requests, isEmpty);
    expect(progress.single.receivedBytes, payload.length);
  });

  test('setzt einen Teil-Download per Range fort', () async {
    store.seedPartial('m', 'a.onnx', payload.sublist(0, 400));
    final server = FakeServer({'a.onnx': payload});
    final progress = <int>[];
    await ModelDownloader(client: server.client, store: store).download(
      model([file('a.onnx', payload)]),
      onProgress: (p) => progress.add(p.receivedBytes),
    );
    expect(server.requests.single.headers['Range'], 'bytes=400-');
    expect(store.finalBytes('m', 'a.onnx'), payload);
    expect(progress.first, 400);
    expect(progress.last, 1000);
  });

  test('Server ignoriert Range (200): Neustart von vorn', () async {
    store.seedPartial('m', 'a.onnx', payload.sublist(0, 400));
    final server = FakeServer({'a.onnx': payload}, ignoreRange: true);
    await ModelDownloader(
      client: server.client,
      store: store,
    ).download(model([file('a.onnx', payload)]));
    expect(store.finalBytes('m', 'a.onnx'), payload);
  });

  test('falsche Prüfsumme: Datei verworfen, nichts committet', () async {
    final server = FakeServer({'a.onnx': payload});
    final m = model([file('a.onnx', payload, sha: 'ab' * 32)]);
    final d = ModelDownloader(client: server.client, store: store);
    await expectLater(d.download(m), downloadError(DownloadErrorKind.checksum));
    expect(await store.exists('m', 'a.onnx'), isFalse);
    expect(await store.partialLength('m', 'a.onnx'), 0);
    expect(store.commits, 0);
  });

  test(
    'falsche Prüfsumme auch nach Fortsetzen (alter Teil wird mitgehasht)',
    () async {
      final corrupt = [...payload.sublist(0, 400).map((b) => b ^ 1)];
      store.seedPartial('m', 'a.onnx', corrupt);
      final server = FakeServer({'a.onnx': payload});
      final d = ModelDownloader(client: server.client, store: store);
      await expectLater(
        d.download(model([file('a.onnx', payload)])),
        downloadError(DownloadErrorKind.checksum),
      );
      expect(store.commits, 0);
      // The next attempt starts from scratch and succeeds.
      await d.download(model([file('a.onnx', payload)]));
      expect(store.finalBytes('m', 'a.onnx'), payload);
    },
  );

  test(
    'vollständiger, nicht umbenannter Teil wird nur geprüft und committet',
    () async {
      store.seedPartial('m', 'a.onnx', payload);
      final server = FakeServer({'a.onnx': payload});
      await ModelDownloader(
        client: server.client,
        store: store,
      ).download(model([file('a.onnx', payload)]));
      expect(server.requests, isEmpty);
      expect(store.finalBytes('m', 'a.onnx'), payload);
    },
  );

  test('vollständiger Teil mit falscher Prüfsumme wird neu geladen', () async {
    store.seedPartial('m', 'a.onnx', List.filled(payload.length, 0));
    final server = FakeServer({'a.onnx': payload});
    await ModelDownloader(
      client: server.client,
      store: store,
    ).download(model([file('a.onnx', payload)]));
    expect(server.requests.single.headers['Range'], isNull);
    expect(store.finalBytes('m', 'a.onnx'), payload);
  });

  test('zu großer Teil wird verworfen', () async {
    store.seedPartial('m', 'a.onnx', List.filled(payload.length + 5, 0));
    final server = FakeServer({'a.onnx': payload});
    await ModelDownloader(
      client: server.client,
      store: store,
    ).download(model([file('a.onnx', payload)]));
    expect(store.finalBytes('m', 'a.onnx'), payload);
  });

  test('416 auf Range: Teil verwerfen und einmal neu versuchen', () async {
    store.seedPartial('m', 'a.onnx', payload.sublist(0, 400));
    final server = FakeServer({'a.onnx': payload})..nextStatus = 416;
    await ModelDownloader(
      client: server.client,
      store: store,
    ).download(model([file('a.onnx', payload)]));
    expect(server.requests, hasLength(2));
    expect(server.requests.last.headers['Range'], isNull);
    expect(store.finalBytes('m', 'a.onnx'), payload);
  });

  test('HTTP-Fehler', () async {
    final server = FakeServer({'a.onnx': payload})..nextStatus = 404;
    await expectLater(
      ModelDownloader(
        client: server.client,
        store: store,
      ).download(model([file('a.onnx', payload)])),
      downloadError(DownloadErrorKind.http),
    );
  });

  test('206 ohne Range-Anfrage ist ein Fehler', () async {
    final server = FakeServer({'a.onnx': payload})..nextStatus = 206;
    await expectLater(
      ModelDownloader(
        client: server.client,
        store: store,
      ).download(model([file('a.onnx', payload)])),
      downloadError(DownloadErrorKind.http),
    );
  });

  test('Netzwerkfehler beim Verbinden', () async {
    final client = MockClient((_) => throw const SocketLikeException());
    await expectLater(
      ModelDownloader(
        client: client,
        store: store,
      ).download(model([file('a.onnx', payload)])),
      downloadError(DownloadErrorKind.network),
    );
  });

  test('Abbruch beim Verbinden', () async {
    final cancel = CancelToken();
    final client = MockClient((_) {
      cancel.cancel();
      throw http.RequestAbortedException();
    });
    await expectLater(
      ModelDownloader(
        client: client,
        store: store,
      ).download(model([file('a.onnx', payload)]), cancel: cancel),
      downloadError(DownloadErrorKind.cancelled),
    );
  });

  test(
    'Netzwerkfehler mitten im Body: Teil bleibt, Fortsetzen klappt',
    () async {
      final server = FakeServer({'a.onnx': payload})..failAfter = 500;
      final d = ModelDownloader(client: server.client, store: store);
      final m = model([file('a.onnx', payload)]);
      await expectLater(
        d.download(m),
        downloadError(DownloadErrorKind.network),
      );
      expect(await store.partialLength('m', 'a.onnx'), 500);
      server.failAfter = null;
      await d.download(m);
      expect(server.requests.last.headers['Range'], 'bytes=500-');
      expect(store.finalBytes('m', 'a.onnx'), payload);
    },
  );

  test(
    'Abbruch während des Downloads behält den Teil, danach Fortsetzen',
    () async {
      final server = FakeServer({'a.onnx': payload})..hangAfter = 300;
      final d = ModelDownloader(client: server.client, store: store);
      final m = model([file('a.onnx', payload)]);
      final cancel = CancelToken();
      final run = d.download(
        m,
        cancel: cancel,
        onProgress: (p) {
          if (p.receivedBytes == 300) {
            Timer(const Duration(milliseconds: 10), cancel.cancel);
          }
        },
      );
      await expectLater(run, downloadError(DownloadErrorKind.cancelled));
      expect(await store.partialLength('m', 'a.onnx'), 300);
      expect(store.commits, 0);

      server.hangAfter = null;
      await d.download(m);
      expect(server.requests.last.headers['Range'], 'bytes=300-');
      expect(store.finalBytes('m', 'a.onnx'), payload);
    },
  );

  test('Abbruch zwischen zwei Chunks', () async {
    final server = FakeServer({'a.onnx': payload});
    final cancel = CancelToken();
    await expectLater(
      ModelDownloader(client: server.client, store: store).download(
        model([file('a.onnx', payload)]),
        cancel: cancel,
        onProgress: (p) {
          if (p.receivedBytes >= 200) cancel.cancel();
        },
      ),
      downloadError(DownloadErrorKind.cancelled),
    );
    expect(await store.partialLength('m', 'a.onnx'), 200);
  });

  test('schon abgebrochener Token: nichts wird angefragt', () async {
    final server = FakeServer({'a.onnx': payload});
    await expectLater(
      ModelDownloader(client: server.client, store: store).download(
        model([file('a.onnx', payload)]),
        cancel: CancelToken()..cancel(),
      ),
      downloadError(DownloadErrorKind.cancelled),
    );
    expect(server.requests, isEmpty);
  });

  test(
    'Server liefert mehr als erwartet: Größenfehler, Teil verworfen',
    () async {
      final server = FakeServer({'a.onnx': payload});
      final m = model([
        ModelFile(
          name: 'a.onnx',
          url: 'https://models.example/a.onnx',
          sizeBytes: 900,
          sha256: payloadSha,
        ),
      ]);
      await expectLater(
        ModelDownloader(client: server.client, store: store).download(m),
        downloadError(DownloadErrorKind.size),
      );
      expect(await store.partialLength('m', 'a.onnx'), 0);
    },
  );

  test(
    'Server liefert zu wenig: Größenfehler, Teil bleibt zum Fortsetzen',
    () async {
      final server = FakeServer({'a.onnx': payload.sublist(0, 600)});
      final m = model([file('a.onnx', payload)]);
      await expectLater(
        ModelDownloader(client: server.client, store: store).download(m),
        downloadError(DownloadErrorKind.size),
      );
      expect(await store.partialLength('m', 'a.onnx'), 600);
    },
  );

  test('Speicherfehler wird als storage gemeldet', () async {
    store.nextAppendError = StateError('Speicher voll');
    final server = FakeServer({'a.onnx': payload});
    final error = await ModelDownloader(client: server.client, store: store)
        .download(model([file('a.onnx', payload)]))
        .then<Object?>((_) => null, onError: (Object e) => e);
    expect(error, isA<ModelDownloadException>());
    error as ModelDownloadException;
    expect(error.kind, DownloadErrorKind.storage);
    expect(error.cause, isA<StateError>());
    expect(error.file, 'a.onnx');
    expect(error.toString(), contains('storage'));
  });
}
