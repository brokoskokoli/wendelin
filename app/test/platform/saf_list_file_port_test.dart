import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/saf_list_file_port.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

const _channel = MethodChannel(filesChannelName);

/// Dart stand-in for `FilesChannel.kt`: documents as raw bytes, `wt`
/// semantics (write replaces everything), error codes like the native side.
final class FakeSafNative {
  final docs = <String, Uint8List>{};
  final revoked = <String>{};
  final released = <String>[];
  final tooLarge = <String>{};
  bool noPicker = false;
  String? nextPick;
  bool hang = false;
  var _n = 0;

  String newUri() => 'content://test/document/${++_n}';

  Future<Object?> handle(MethodCall call) async {
    final args = (call.arguments as Map<Object?, Object?>?) ?? const {};
    final uri = args['uri'] as String?;
    if (hang) return Completer<Object?>().future;
    switch (call.method) {
      case 'hasAccess':
        return uri != null && !revoked.contains(uri);
      case 'release':
        released.add(uri!);
        return null;
    }
    // Like FilesChannel.kt: a lost grant is a SecurityException for every
    // access, including exists (never a silent false).
    if (uri != null && revoked.contains(uri)) {
      throw PlatformException(code: 'permissionDenied');
    }
    if (uri != null && tooLarge.contains(uri)) {
      throw PlatformException(code: 'tooLarge');
    }
    switch (call.method) {
      case 'read':
        final bytes = docs[uri];
        if (bytes == null) throw PlatformException(code: 'notFound');
        return bytes;
      case 'write':
        docs[uri!] = args['bytes']! as Uint8List;
        return null;
      case 'exists':
        return docs.containsKey(uri);
      case 'openDocument':
        if (noPicker) throw PlatformException(code: 'unsupported');
        return nextPick;
      case 'createDocument':
        final created = newUri();
        docs[created] = Uint8List(0);
        return created;
      case 'displayName':
        return docs.containsKey(uri) ? 'Einkaufen.md' : null;
    }
    throw MissingPluginException(call.method);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeSafNative native;

  setUp(() {
    native = FakeSafNative();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, native.handle);
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );

  listFilePortContract(
    () => (
      port: SafListFilePort(),
      newHandle: native.newUri,
      delete: (String h) => native.docs.remove(h),
      reopen: SafListFilePort.new,
    ),
    name: 'SafListFilePort',
  );

  Matcher port(PortErrorKind kind) =>
      throwsA(isA<PortException>().having((e) => e.kind, 'kind', kind));

  test('Bytes gehen unverändert über den Kanal (BOM, CRLF, Unicode)', () async {
    const text = '﻿# Einkaufen\r\n- [ ] Grüße 🌊\r\n- [x] Brot';
    final uri = native.newUri();
    await SafListFilePort().write(uri, text);
    expect(native.docs[uri], utf8.encode(text));
    expect(await SafListFilePort().read(uri), text);
  });

  test(
    'entzogene Rechte: permissionDenied mit Hinweis auf Einstellungen',
    () async {
      final uri = native.newUri();
      native.revoked.add(uri);
      await expectLater(
        SafListFilePort().read(uri),
        port(PortErrorKind.permissionDenied),
      );
      try {
        await SafListFilePort().read(uri);
      } on PortException catch (e) {
        expect(e.message, contains('Einstellungen'));
      }
    },
  );

  test('entzogene Rechte: auch exists meldet permissionDenied', () async {
    final uri = native.newUri();
    native.docs[uri] = Uint8List(0);
    native.revoked.add(uri);
    await expectLater(
      SafListFilePort().exists(uri),
      port(PortErrorKind.permissionDenied),
    );
    expect(await const DocumentPicker().hasAccess(uri), isFalse);
    native.revoked.clear();
    expect(await const DocumentPicker().hasAccess(uri), isTrue);
    expect(await SafListFilePort().exists(uri), isTrue);
  });

  test('zu große Datei: rejected', () async {
    final uri = native.newUri();
    native.tooLarge.add(uri);
    await expectLater(
      SafListFilePort().read(uri),
      port(PortErrorKind.rejected),
    );
  });

  test('keine Dateiauswahl auf dem Gerät: unsupported', () async {
    native.noPicker = true;
    await expectLater(
      const DocumentPicker().open(),
      port(PortErrorKind.unsupported),
    );
  });

  test('kein UTF-8: failed', () async {
    final uri = native.newUri();
    native.docs[uri] = Uint8List.fromList([0xff, 0xfe, 0x00, 0xd8]);
    await expectLater(SafListFilePort().read(uri), port(PortErrorKind.failed));
  });

  test('hängender Anbieter: nach dem Zeitlimit unavailable', () async {
    native.hang = true;
    final p = SafListFilePort(timeout: const Duration(milliseconds: 20));
    await expectLater(p.read('content://x'), port(PortErrorKind.unavailable));
    await expectLater(
      p.write('content://x', 'a'),
      port(PortErrorKind.unavailable),
    );
  });

  test('ohne Plattform: unsupported', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    await expectLater(
      SafListFilePort().exists('content://x'),
      port(PortErrorKind.unsupported),
    );
    await expectLater(
      const DocumentPicker().open(),
      port(PortErrorKind.unsupported),
    );
  });

  group('DocumentPicker', () {
    test('öffnen, abbrechen, anlegen, Name, freigeben', () async {
      const picker = DocumentPicker();
      native.nextPick = 'content://picked/1';
      expect(await picker.open(), 'content://picked/1');
      native.nextPick = null;
      expect(await picker.open(), isNull, reason: 'abgebrochen');
      final created = await picker.create('Einkaufen.md');
      expect(created, isNotNull);
      expect(await SafListFilePort().exists(created!), isTrue);
      expect(await picker.displayName(created), 'Einkaufen.md');
      await picker.release(created);
      expect(native.released, [created]);
    });

    test('Fehlercodes', () {
      expect(
        portExceptionForFileError('notFound').kind,
        PortErrorKind.notFound,
      );
      expect(
        portExceptionForFileError('permissionDenied').kind,
        PortErrorKind.permissionDenied,
      );
      expect(portExceptionForFileError('x').kind, PortErrorKind.failed);
    });
  });
}
