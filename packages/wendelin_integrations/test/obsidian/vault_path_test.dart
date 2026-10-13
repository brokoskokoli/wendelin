// Abnahme: Pfad-Sicherheit tabellengetestet (.., absolute Pfade, .obsidian,
// versteckte Ordner, Steuerzeichen, Prozent-Kodierung, Symlinks).
import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

void main() {
  group('VaultPath.normalize erlaubt', () {
    const ok = {
      'Notiz.md': 'Notiz.md',
      'Projekte/Wendelin.md': 'Projekte/Wendelin.md',
      '  Projekte/Wendelin.md  ': 'Projekte/Wendelin.md',
      'Projekte//Wendelin.md': 'Projekte/Wendelin.md',
      './Projekte/./Wendelin.md': 'Projekte/Wendelin.md',
      'Projekte/': 'Projekte',
      'Ordner mit Leerzeichen/Grüße 🥛.md':
          'Ordner mit Leerzeichen/Grüße 🥛.md',
      'a.b/c..d.md': 'a.b/c..d.md',
      'Notiz...md': 'Notiz...md',
      '2026-10-13.md': '2026-10-13.md',
      '100%.md': '100%.md',
    };
    for (final MapEntry(key: input, value: want) in ok.entries) {
      test('„$input“ → „$want“', () {
        expect(VaultPath.normalize(input), want);
      });
    }
    test('Wurzel nur mit allowRoot', () {
      expect(VaultPath.normalize('', allowRoot: true), '');
      expect(VaultPath.normalize('./', allowRoot: true), '');
      expect(() => VaultPath.normalize(''), throwsA(isA<PortException>()));
    });
  });

  group('VaultPath.normalize weist ab', () {
    const bad = {
      '..': '„..“',
      '../aussen.md': '„..“',
      'a/../../aussen.md': '„..“',
      'a/..': '„..“',
      'a/%2e%2e/b.md': '„..“',
      '%2E%2E/b.md': '„..“',
      '/etc/passwd': 'relativ',
      '/Notiz.md': 'relativ',
      '~/Notiz.md': 'relativ',
      'C:/Users/x.md': 'Laufwerk',
      'c:x.md': 'Laufwerk',
      'file:///etc/passwd': 'Adresse',
      'content://com.android/x': 'Adresse',
      r'a\b.md': '„/“',
      r'..\aussen.md': '„/“',
      '.obsidian/app.json': 'Konfigurationsordner',
      '.OBSIDIAN/app.json': 'Konfigurationsordner',
      'a/.obsidian': 'Konfigurationsordner',
      '%2eobsidian/app.json': 'Konfigurationsordner',
      '.trash/alt.md': 'versteckt',
      '.git/config': 'versteckt',
      'Ordner/.versteckt.md': 'versteckt',
      'Notiz\u0000.md': 'Steuerzeichen',
      'Zeile\nzwei.md': 'Steuerzeichen',
    };
    for (final MapEntry(key: input, value: why) in bad.entries) {
      test(input.replaceAll('\u0000', r'\0').replaceAll('\n', r'\n'), () {
        expect(
          () => VaultPath.normalize(input, allowRoot: true),
          throwsA(
            isA<PortException>()
                .having((e) => e.kind, 'kind', PortErrorKind.rejected)
                .having((e) => e.message, 'message', contains(why)),
          ),
        );
      });
    }
    test('zu lange Pfade und Namen', () {
      expect(
        () => VaultPath.normalize('a/' * 600),
        throwsA(isA<PortException>()),
      );
      expect(
        () => VaultPath.normalize('${'x' * 256}.md'),
        throwsA(isA<PortException>()),
      );
    });
    test('ungültige Prozent-Kodierung bleibt Text', () {
      expect(VaultPath.normalize('%zz.md'), '%zz.md');
    });
  });

  group('Notizpfade', () {
    test('.md wird ergänzt, auch bei Punkten im Namen', () {
      expect(VaultPath.note('Projekte/Wendelin'), 'Projekte/Wendelin.md');
      expect(VaultPath.note('Wendelin.MD'), 'Wendelin.MD');
      expect(VaultPath.note('Treffen 12.10.'), 'Treffen 12.10..md');
    });
    test('neue Notizen ohne von Obsidian verbotene Zeichen', () {
      for (final bad in ['a*b', 'a"b', 'a<b', 'a>b', 'a|b', 'a?b']) {
        expect(
          () => VaultPath.newNote(bad),
          throwsA(isA<PortException>()),
          reason: bad,
        );
      }
      expect(VaultPath.newNote('Ideen/Neu'), 'Ideen/Neu.md');
    });
    test('Hilfen', () {
      expect(VaultPath.title('a/b/Notiz.md'), 'Notiz');
      expect(VaultPath.title('a/Bild.png'), 'Bild.png');
      expect(VaultPath.parent('a/b/c.md'), 'a/b');
      expect(VaultPath.parent('c.md'), '');
      expect(VaultPath.join('', 'x'), 'x');
      expect(VaultPath.join('a', 'x'), 'a/x');
      expect(VaultPath.isHidden('a/.b/c'), isTrue);
      expect(VaultPath.isHidden('a/b.c'), isFalse);
    });
  });

  group('Tools weisen unsichere Pfade ab, ohne den Port zu berühren', () {
    final env = (
      vault: FakeVaultPort(files: {'Ok.md': 'x'}),
      index: FakeNoteIndex(),
    );
    final integration = ObsidianIntegration(
      env.vault,
      env.index,
      settings: () => const ObsidianSettings(vaultName: 'V'),
    );
    Tool tool(String name) =>
        integration.tools.singleWhere((t) => t.name == name);
    const paths = [
      '../aussen',
      '/etc/passwd',
      '.obsidian/workspace',
      'a/../../x',
      r'..\x',
    ];
    final calls = <String, Map<String, Object?> Function(String)>{
      'obsidian__read_note': (p) => {'path': p},
      'obsidian__list_folder': (p) => {'folder': p},
      'obsidian__create_note': (p) => {'path': p, 'content': 'x'},
      'obsidian__append_to_note': (p) => {'path': p, 'text': 'x'},
      'obsidian__replace_section': (p) => {
        'path': p,
        'heading': 'A',
        'content': 'x',
      },
      'obsidian__open_note': (p) => {'path': p},
    };
    for (final MapEntry(key: name, value: args) in calls.entries) {
      for (final p in paths) {
        test('$name „$p“', () async {
          env.vault.methodCalls.clear();
          final o = await tool(name).execute(args(p), ctx());
          expect(o.isError, isTrue);
          expect(o.text, contains('Pfad'));
          expect(env.vault.methodCalls, isEmpty);
          expect(env.vault.files.keys, ['Ok.md']);
        });
      }
    }
    test(
      'Tagesnotiz-Ordner aus den Einstellungen wird ebenso geprüft',
      () async {
        final i = ObsidianIntegration(
          env.vault,
          env.index,
          settings: () => const ObsidianSettings(
            dailyNotes: DailyNoteSettings(folder: '../aussen'),
          ),
        );
        final o = await i.tools
            .singleWhere((t) => t.name == 'obsidian__append_daily_note')
            .execute({'text': 'x'}, ctx());
        expect(o.isError, isTrue);
        expect(env.vault.files.keys, ['Ok.md']);
      },
    );
  });

  group('FileSystemVaultPort und Symlinks', () {
    late Directory base;
    late Directory vaultDir;
    late FileSystemVaultPort port;

    setUp(() {
      base = Directory.systemTemp.createTempSync('vault_links');
      vaultDir = Directory('${base.path}/vault')..createSync();
      Directory('${base.path}/geheim').createSync();
      File('${base.path}/geheim/passwort.md').writeAsStringSync('geheim');
      File('${vaultDir.path}/Notiz.md').writeAsStringSync('# Notiz\n');
      Directory('${vaultDir.path}/Innen').createSync();
      File('${vaultDir.path}/Innen/Ziel.md').writeAsStringSync('innen');
      Link('${vaultDir.path}/Raus').createSync('${base.path}/geheim');
      Link('${vaultDir.path}/raus.md')
          .createSync('${base.path}/geheim/passwort.md');
      Link('${vaultDir.path}/Verweis').createSync('${vaultDir.path}/Innen');
      Link('${vaultDir.path}/kaputt.md').createSync('${base.path}/fehlt.md');
      port = FileSystemVaultPort(vaultDir);
    });

    tearDown(() => base.deleteSync(recursive: true));

    Matcher rejected() => throwsA(
      isA<PortException>().having(
        (e) => e.kind,
        'kind',
        PortErrorKind.rejected,
      ),
    );

    test('Links nach außen: nicht gelistet, Zugriff abgewiesen', () async {
      final names = (await port.list('')).map((e) => e.path).toSet();
      expect(names, {'Notiz.md', 'Innen', 'Verweis'});
      await expectLater(port.read('raus.md'), rejected());
      await expectLater(port.read('Raus/passwort.md'), rejected());
      await expectLater(port.list('Raus'), rejected());
      await expectLater(port.write('Raus/neu.md', 'x'), rejected());
      await expectLater(port.write('raus.md', 'x'), rejected());
      await expectLater(port.create('Raus/neu.md', 'x'), rejected());
      await expectLater(port.exists('Raus/passwort.md'), rejected());
      expect(
        File('${base.path}/geheim/passwort.md').readAsStringSync(),
        'geheim',
      );
      expect(File('${base.path}/geheim/neu.md').existsSync(), isFalse);
    });

    test('kaputte Links werden abgewiesen', () async {
      await expectLater(port.read('kaputt.md'), rejected());
    });

    test('Links innerhalb des Vaults funktionieren', () async {
      expect(await port.read('Verweis/Ziel.md'), 'innen');
      final inner = await port.list('Verweis');
      expect(inner.single.path, 'Verweis/Ziel.md');
      expect(
        (await port.list('')).singleWhere((e) => e.path == 'Verweis').isFolder,
        isTrue,
      );
    });

    test('Index-Sync liest nichts hinter Links nach außen', () async {
      final index = FakeNoteIndex();
      await NoteIndexer(port, index).sync();
      expect(index.notes.keys.toSet(), {
        'Notiz.md',
        'Innen/Ziel.md',
        'Verweis/Ziel.md',
      });
    });

    test('write in einen Ordner wird abgewiesen, ohne Temp-Reste', () async {
      await expectLater(port.write('Innen', 'x'), rejected());
      await port.write('Innen/Neu.md', 'neu');
      expect(
        Directory('${vaultDir.path}/Innen')
            .listSync()
            .map((e) => e.path.split('/').last)
            .toSet(),
        {'Ziel.md', 'Neu.md'},
      );
    });

    test('delete auf einen Ordner ist notFound', () async {
      await expectLater(port.delete('Innen'), throwsA(isA<PortException>()));
    });
  });
}
