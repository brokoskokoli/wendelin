import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';

import '../src/common/port_exception.dart';
import '../src/obsidian/ports.dart';

/// What [vaultPortContract] needs: a port on an **empty** vault and,
/// optionally, a second independent port instance on the same storage
/// ([reopen], e.g. after an app restart) and a cleanup step.
typedef VaultContractSetup = ({
  VaultPort port,
  FutureOr<VaultPort> Function()? reopen,
  FutureOr<void> Function()? dispose,
});

/// Creates the setup for one check.
typedef VaultPortFactory = FutureOr<VaultContractSetup> Function();

/// Names of the checks in [vaultPortContractChecks].
abstract final class VaultPortChecks {
  /// Missing paths: exists false, the rest notFound.
  static const missing = 'fehlende Pfade: exists false, sonst notFound';

  /// write creates the file and its parent folders.
  static const create = 'write legt Datei und Ordner an, list zeigt sie';

  /// Content survives character for character.
  static const exact =
      'Inhalt bleibt zeichengenau (BOM, CRLF, CR, ohne Schlussumbruch, '
      'Unicode, 300 KB)';

  /// A shorter write truncates.
  static const truncate = 'kürzerer Inhalt überschreibt vollständig';

  /// create refuses existing files without changing them.
  static const createExclusive = 'create: neue Datei ja, vorhandene rejected';

  /// delete removes the file.
  static const delete = 'delete entfernt die Datei';

  /// modifiedAt changes with every write; size counts UTF-8 bytes.
  static const metadata =
      'modifiedAt ändert sich bei jedem write, size zählt UTF-8-Bytes, '
      'list liefert dieselben Werte';

  /// Unsafe paths are rejected and nothing is written.
  static const unsafe =
      'unsichere Pfade (.., absolut, .obsidian, versteckt) werden '
      'abgewiesen';

  /// A second instance reads what the first wrote (if reopen is given).
  static const persisted = 'zweite Port-Instanz liest den Inhalt wieder';
}

/// Reusable contract suite for every [VaultPort] (`FakeVaultPort`,
/// `FileSystemVaultPort`, the app's SAF port); registers one test per
/// entry of [vaultPortContractChecks].
void vaultPortContract(VaultPortFactory create, {String name = 'VaultPort'}) {
  group('$name erfüllt den VaultPort-Vertrag', () {
    vaultPortContractChecks(create).forEach(test);
  });
}

Matcher _port(PortErrorKind kind) =>
    throwsA(isA<PortException>().having((e) => e.kind, 'kind', kind));

/// The checks of [vaultPortContract] by name ([VaultPortChecks]).
Map<String, Future<void> Function()> vaultPortContractChecks(
  VaultPortFactory create,
) {
  Future<void> withVault(
    Future<void> Function(VaultPort port, VaultContractSetup s) body,
  ) async {
    final s = await create();
    try {
      await body(s.port, s);
    } finally {
      await s.dispose?.call();
    }
  }

  Future<void> roundTrip(VaultPort p, String path, String content) async {
    await p.write(path, content);
    final back = await p.read(path);
    expect(back.length, content.length, reason: 'Länge');
    expect(back, content);
  }

  return {
    VaultPortChecks.missing: () => withVault((p, _) async {
      expect(await p.exists('Fehlt.md'), isFalse);
      expect(await p.exists('Ordner/Fehlt.md'), isFalse);
      await expectLater(p.read('Fehlt.md'), _port(PortErrorKind.notFound));
      await expectLater(
        p.modifiedAt('Fehlt.md'),
        _port(PortErrorKind.notFound),
      );
      await expectLater(p.size('Fehlt.md'), _port(PortErrorKind.notFound));
      await expectLater(p.delete('Fehlt.md'), _port(PortErrorKind.notFound));
      await expectLater(p.list('Fehlt'), _port(PortErrorKind.notFound));
      expect(await p.list(''), isEmpty);
    }),
    VaultPortChecks.create: () => withVault((p, _) async {
      await p.write('Projekte/Neu/Idee.md', '# Idee\n');
      expect(await p.exists('Projekte/Neu/Idee.md'), isTrue);
      expect(await p.exists('Projekte'), isTrue);
      expect(await p.read('Projekte/Neu/Idee.md'), '# Idee\n');
      final root = await p.list('');
      expect(root.map((e) => (e.path, e.isFolder)), [('Projekte', true)]);
      final inner = await p.list('Projekte/Neu');
      expect(inner.map((e) => (e.path, e.isFolder, e.name)), [
        ('Projekte/Neu/Idee.md', false, 'Idee.md'),
      ]);
    }),
    VaultPortChecks.exact: () => withVault((p, _) async {
      await roundTrip(
        p,
        'Exakt.md',
        '\uFEFF---\r\ntags: [x]\r\n---\r\n# Grüße ‚Milch‘ 🥛\r\n'
            '\t- [x] Unterpunkt\r\n\r\nEnde ohne Umbruch',
      );
      await roundTrip(p, 'Exakt.md', 'nur\nLF\n\n');
      await roundTrip(p, 'Exakt.md', 'altes\rMac\r');
      await roundTrip(p, 'Exakt.md', '');
      await roundTrip(
        p,
        'Groß.md',
        List.generate(10000, (i) => 'Zeile $i äöü').join('\n'),
      );
    }),
    VaultPortChecks.truncate: () => withVault((p, _) async {
      await p.write('Kurz.md', 'x' * 5000);
      await roundTrip(p, 'Kurz.md', 'kurz\n');
    }),
    VaultPortChecks.createExclusive: () => withVault((p, _) async {
      await p.create('Ordner/Neu.md', 'erst\n');
      expect(await p.read('Ordner/Neu.md'), 'erst\n');
      await expectLater(
        p.create('Ordner/Neu.md', 'zweit\n'),
        _port(PortErrorKind.rejected),
      );
      expect(await p.read('Ordner/Neu.md'), 'erst\n');
    }),
    VaultPortChecks.delete: () => withVault((p, _) async {
      await p.write('A/Weg.md', 'x');
      await p.write('A/Bleibt.md', 'y');
      await p.delete('A/Weg.md');
      expect(await p.exists('A/Weg.md'), isFalse);
      await expectLater(p.read('A/Weg.md'), _port(PortErrorKind.notFound));
      expect((await p.list('A')).map((e) => e.path), ['A/Bleibt.md']);
    }),
    VaultPortChecks.metadata: () => withVault((p, _) async {
      await p.write('M.md', 'äb');
      final m1 = await p.modifiedAt('M.md');
      expect(await p.size('M.md'), utf8.encode('äb').length);
      await p.write('M.md', 'neu');
      final m2 = await p.modifiedAt('M.md');
      expect(m2.isAtSameMomentAs(m1), isFalse, reason: 'modifiedAt');
      expect(await p.size('M.md'), 3);
      final e = (await p.list('')).single;
      if (e.modifiedAt != null) {
        expect(e.modifiedAt!.isAtSameMomentAs(m2), isTrue);
      }
      if (e.size != null) expect(e.size, 3);
    }),
    VaultPortChecks.unsafe: () => withVault((p, _) async {
      for (final bad in [
        '../aussen.md',
        'a/../../aussen.md',
        '/etc/passwd',
        '.obsidian/app.json',
        'Ordner/.versteckt.md',
        'C:/x.md',
      ]) {
        await expectLater(
          p.write(bad, 'x'),
          _port(PortErrorKind.rejected),
          reason: bad,
        );
        await expectLater(
          p.read(bad),
          _port(PortErrorKind.rejected),
          reason: bad,
        );
        await expectLater(
          p.list(bad),
          _port(PortErrorKind.rejected),
          reason: bad,
        );
      }
      expect(await p.list(''), isEmpty);
    }),
    VaultPortChecks.persisted: () => withVault((p, s) async {
      final reopen = s.reopen;
      // Ohne zweite Instanz nicht prüfbar.
      if (reopen == null) return;
      await p.write('Bleibt/Da.md', '# Da\r\n');
      final second = await reopen();
      expect(await second.exists('Bleibt/Da.md'), isTrue);
      expect(await second.read('Bleibt/Da.md'), '# Da\r\n');
    }),
  };
}
