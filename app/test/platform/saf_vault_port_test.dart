import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/saf_vault_port.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

const _channel = MethodChannel(vaultChannelName);
const _tree =
    'content://com.android.externalstorage.documents/tree/primary%3AVault';

/// Dart stand-in for `VaultChannel.kt`: a document tree resolved segment
/// by segment, `wt` writes, parents created on write, exclusive create,
/// error codes like the native side.
final class FakeVaultNative {
  /// Path → content (files) or `null` (folders); '' is the root.
  final nodes = <String, Uint8List?>{'': null};
  final modified = <String, int>{};
  final calls = <MethodCall>[];
  final released = <String>[];
  bool revoked = false;
  bool hang = false;
  bool noPicker = false;
  Map<String, String>? nextPick;
  var _clock = 1760000000000;

  bool isFolder(String p) => nodes.containsKey(p) && nodes[p] == null;

  String _parent(String p) =>
      p.contains('/') ? p.substring(0, p.lastIndexOf('/')) : '';

  Map<String, Object?> _entry(String p) => {
    'name': p.split('/').last,
    'folder': isFolder(p),
    'modified': isFolder(p) ? null : modified[p],
    'size': isFolder(p) ? null : nodes[p]!.length,
  };

  void _write(String p, Uint8List bytes) {
    final segments = p.split('/');
    for (var i = 1; i < segments.length; i++) {
      final folder = segments.take(i).join('/');
      if (!nodes.containsKey(folder)) {
        nodes[folder] = null;
      } else if (!isFolder(folder)) {
        throw PlatformException(code: 'rejected');
      }
    }
    nodes[p] = bytes;
    modified[p] = ++_clock;
  }

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    final args = (call.arguments as Map<Object?, Object?>?) ?? const {};
    if (hang) return Completer<Object?>().future;
    switch (call.method) {
      case 'pickTree':
        if (noPicker) throw PlatformException(code: 'unsupported');
        return nextPick;
      case 'hasAccess':
        return !revoked && args['tree'] == _tree;
      case 'release':
        released.add(args['tree']! as String);
        return null;
    }
    if (revoked) throw PlatformException(code: 'permissionDenied');
    final path = args['path']! as String;
    if (path.split('/').any((s) => s == '..' || s == '.')) {
      throw PlatformException(code: 'rejected');
    }
    switch (call.method) {
      case 'list':
        if (!isFolder(path)) throw PlatformException(code: 'notFound');
        return [
          for (final p in nodes.keys)
            if (p.isNotEmpty && _parent(p) == path) _entry(p),
        ];
      case 'stat':
        return nodes.containsKey(path) ? _entry(path) : null;
      case 'read':
        if (!nodes.containsKey(path)) throw PlatformException(code: 'notFound');
        if (isFolder(path)) throw PlatformException(code: 'isFolder');
        return nodes[path];
      case 'write':
        if (isFolder(path)) throw PlatformException(code: 'isFolder');
        _write(path, args['bytes']! as Uint8List);
        return null;
      case 'create':
        if (nodes.containsKey(path)) throw PlatformException(code: 'exists');
        _write(path, args['bytes']! as Uint8List);
        return null;
      case 'delete':
        if (!nodes.containsKey(path)) throw PlatformException(code: 'notFound');
        if (isFolder(path)) throw PlatformException(code: 'isFolder');
        nodes.remove(path);
        return null;
    }
    throw MissingPluginException(call.method);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeVaultNative native;

  setUp(() {
    native = FakeVaultNative();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, native.handle);
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );

  SafVaultPort port() => SafVaultPort(tree: () => _tree);

  vaultPortContract(
    () => (port: port(), reopen: port, dispose: null),
    name: 'SafVaultPort',
  );

  Matcher fails(PortErrorKind kind, [String? text]) => throwsA(
    isA<PortException>()
        .having((e) => e.kind, 'kind', kind)
        .having((e) => e.message, 'message', contains(text ?? '')),
  );

  test('Bytes gehen unverändert über den Kanal (BOM, CRLF, Unicode)', () async {
    const text = '﻿# Tag\r\n- Grüße 🌊\r\nEnde';
    await port().write('Journal/2026-10-13.md', text);
    expect(native.nodes['Journal/2026-10-13.md'], utf8.encode(text));
    expect(await port().read('Journal/2026-10-13.md'), text);
  });

  test(
    'list liefert Zeit und Größe aus einer Abfrage (kein stat je Datei)',
    () async {
      await port().write('A/x.md', 'äb');
      await port().write('A/B/y.md', 'y');
      native.calls.clear();
      final entries = await port().list('A');
      expect(native.calls.map((c) => c.method), ['list']);
      final file = entries.singleWhere((e) => e.path == 'A/x.md');
      expect(file.size, 3);
      expect(file.modifiedAt, isNotNull);
      expect(entries.singleWhere((e) => e.path == 'A/B').isFolder, isTrue);
    },
  );

  test(
    'Pfade werden vor dem Kanal geprüft (nichts Unsicheres geht raus)',
    () async {
      for (final bad in ['../x.md', '.obsidian/app.json', '/etc/passwd']) {
        await expectLater(port().read(bad), fails(PortErrorKind.rejected));
      }
      expect(native.calls, isEmpty);
    },
  );

  test(
    'entzogene Rechte: permissionDenied mit Hinweis auf Einstellungen',
    () async {
      native.revoked = true;
      await expectLater(
        port().read('x.md'),
        fails(PortErrorKind.permissionDenied, 'Einstellungen → Obsidian'),
      );
      await expectLater(port().list(''), fails(PortErrorKind.permissionDenied));
    },
  );

  test('Zeitlimit: hängender Provider → unavailable (Schreiben länger)', () {
    native.hang = true;
    final slow = SafVaultPort(
      tree: () => _tree,
      timeout: const Duration(milliseconds: 20),
      writeTimeout: const Duration(milliseconds: 200),
    );
    fakeAsync((fake) {
      Object? readErr;
      Object? writeErr;
      Object? createErr;
      slow.read('x.md').then<void>((_) {}, onError: (Object e) => readErr = e);
      slow
          .write('x.md', 'y')
          .then<void>((_) {}, onError: (Object e) => writeErr = e);
      slow
          .create('n.md', 'y')
          .then<void>((_) {}, onError: (Object e) => createErr = e);
      fake.elapse(const Duration(milliseconds: 25));
      expect(readErr, isNotNull, reason: 'read: 20 ms');
      expect(writeErr, isNull, reason: 'write: writeTimeout 200 ms');
      expect(createErr, isNull, reason: 'create: ebenfalls writeTimeout');
      fake.elapse(const Duration(milliseconds: 150));
      expect(writeErr, isNull);
      fake.elapse(const Duration(milliseconds: 30));
      expect(writeErr, isNotNull);
      for (final e in [readErr, writeErr, createErr]) {
        expect((e as PortException).kind, PortErrorKind.unavailable);
      }
    });
    expect(SafVaultPort(tree: () => _tree).writeTimeout.inSeconds, 30);
  });

  test('ohne gewählten Vault: unavailable, kein Kanalaufruf', () async {
    final none = SafVaultPort(tree: () => null);
    await expectLater(
      none.list(''),
      fails(PortErrorKind.unavailable, 'Kein Obsidian-Vault'),
    );
    expect(native.calls, isEmpty);
  });

  test('kein UTF-8: failed statt kaputtem Text', () async {
    native.nodes['bin.md'] = Uint8List.fromList([0xC3, 0x28]);
    native.modified['bin.md'] = 1;
    await expectLater(port().read('bin.md'), fails(PortErrorKind.failed));
  });

  test('Ordner statt Datei: rejected bzw. notFound', () async {
    await port().write('Ordner/a.md', 'x');
    await expectLater(
      port().write('Ordner', 'x'),
      fails(PortErrorKind.rejected, 'Ordner'),
    );
    await expectLater(
      port().modifiedAt('Ordner'),
      fails(PortErrorKind.notFound),
    );
    await expectLater(port().size('Ordner'), fails(PortErrorKind.notFound));
  });

  test('Fehlercodes werden deutsch übersetzt', () {
    expect(vaultError('tooLarge', 'a.md').kind, PortErrorKind.rejected);
    expect(vaultError('unsupported', '').kind, PortErrorKind.unsupported);
    expect(vaultError('rejected', 'a').message, contains('nicht erlaubt'));
    expect(vaultError('xyz', 'a.md').kind, PortErrorKind.failed);
  });

  test('ohne Plattform-Kanal: unsupported', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    await expectLater(port().read('x.md'), fails(PortErrorKind.unsupported));
    await expectLater(
      const VaultAccess().pick(),
      fails(PortErrorKind.unsupported),
    );
  });

  group('VaultAccess', () {
    test('Auswahl liefert URI und Namen, Abbruch null', () async {
      native.nextPick = {'uri': _tree, 'name': 'Leben'};
      expect(await const VaultAccess().pick(), (uri: _tree, name: 'Leben'));
      native.nextPick = null;
      expect(await const VaultAccess().pick(), isNull);
      native.nextPick = {'uri': _tree, 'name': ''};
      expect((await const VaultAccess().pick())!.name, 'Vault');
    });

    test('keine Ordnerauswahl auf dem Gerät: unsupported', () async {
      native.noPicker = true;
      await expectLater(
        const VaultAccess().pick(),
        fails(PortErrorKind.unsupported),
      );
    });

    test('Rechte prüfen und freigeben', () async {
      expect(await const VaultAccess().hasAccess(_tree), isTrue);
      native.revoked = true;
      expect(await const VaultAccess().hasAccess(_tree), isFalse);
      await const VaultAccess().release(_tree);
      expect(native.released, [_tree]);
    });
  });
}
