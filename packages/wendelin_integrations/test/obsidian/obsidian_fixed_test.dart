import 'package:test/test.dart';

import '../helpers.dart';
import 'obsidian_support.dart';

void main() {
  group('feste Bestätigung', () {
    test('create_note: Titel statt Pfad', () async {
      final obs = Obs();
      final o = await obs.ok('create_note', {
        'path': 'Ideen/Gartenhaus',
        'content': 'x',
      });
      expectFixed(
        o,
        obs.tool('create_note'),
        'note.created',
        de: 'Die Notiz „Gartenhaus“ ist angelegt.',
      );
    });

    test('create_note: vorhandene Notiz → Fehler ohne Satz', () async {
      final obs = Obs(files: {'Da.md': 'alt'});
      final o = await obs.call('create_note', {'path': 'Da', 'content': 'n'});
      expect(o.isError, isTrue);
      expect(o.fixed, isNull);
    });

    test('append_to_note: Notiztitel', () async {
      final obs = Obs(files: {'Ideen/N.md': '# N\n'});
      final o = await obs.ok('append_to_note', {
        'path': 'Ideen/N',
        'text': '- eins',
      });
      expectFixed(
        o,
        obs.tool('append_to_note'),
        'note.appended',
        de: 'Der Text steht jetzt in der Notiz „N“.',
      );
    });

    test('append_to_note: Notiz fehlt → Fehler ohne Satz', () async {
      final obs = Obs();
      final o = await obs.call('append_to_note', {'path': 'Nix', 'text': 'x'});
      expect(o.isError, isTrue);
      expect(o.fixed, isNull);
    });

    test('append_daily_note: Titel der Tagesnotiz', () async {
      final obs = Obs();
      final o = await obs.ok('append_daily_note', {'text': '- Zahnarzt'});
      expectFixed(
        o,
        obs.tool('append_daily_note'),
        'note.appended',
        de: 'Der Text steht jetzt in der Notiz „2026-10-13“.',
      );
    });
  });
}
