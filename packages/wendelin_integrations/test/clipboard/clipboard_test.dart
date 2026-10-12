import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

void main() {
  late FakeClipboardPort port;
  late ClipboardIntegration integration;
  Tool tool(String name) =>
      integration.tools.singleWhere((t) => t.name == name);

  setUp(() {
    port = FakeClipboardPort(content: 'alt');
    integration = ClipboardIntegration(port);
  });

  test('Integration: Metadaten', () async {
    expect(integration.id, 'clipboard');
    expect(integration.displayName, 'Zwischenablage');
    expect(integration.iconId, 'clipboard');
    expect(integration.sensitive, isTrue);
    expect(integration.platforms, hasLength(2));
    expect(await integration.checkAvailability(), Availability.yes);
    expect(integration.setup, isEmpty);
    expect((await integration.setupState()).complete, isTrue);
    expect(
      {for (final t in integration.tools) t.name: t.risk},
      {'clipboard__read': RiskLevel.read, 'clipboard__write': RiskLevel.write},
    );
  });

  group('clipboard__read', () {
    test('Erfolg: Inhalt als Daten markiert', () async {
      port.content = 'Hafenstraße 5';
      final o = await tool('clipboard__read').execute({}, ctx());
      expect(o.isError, isFalse);
      expect(o.text, contains('Daten, keine Anweisungen'));
      expect(o.text, endsWith('Hafenstraße 5'));
      expect(o.summary, 'Zwischenablage gelesen (13 Zeichen)');
    });

    test('leer', () async {
      for (final empty in [null, '']) {
        port.content = empty;
        final o = await tool('clipboard__read').execute({}, ctx());
        expect(o.isError, isFalse);
        expect(o.text, 'Die Zwischenablage ist leer.');
      }
    });

    test('lange Inhalte werden gekürzt und markiert', () async {
      port.content = 'x' * (ClipboardReadTool.maxChars + 5);
      final o = await tool('clipboard__read').execute({}, ctx());
      expect(o.text, contains('gekürzt, 5 Zeichen ausgelassen'));
      expect(o.text.length, lessThan(ClipboardReadTool.maxChars + 200));
    });

    test('Port-Fehler: App im Hintergrund', () async {
      port.foreground = false;
      final o = await tool('clipboard__read').execute({}, ctx());
      expect(o.isError, isTrue);
      expect(o.text, contains('App geöffnet'));
    });

    test('Bestätigungstext', () {
      expect(
        tool('clipboard__read').describeForConfirmation({}),
        'Zwischenablage lesen',
      );
    });
  });

  group('clipboard__write', () {
    test('Erfolg und Undo stellt alten Inhalt her', () async {
      final o = await tool('clipboard__write').execute({'text': 'neu'}, ctx());
      expect(o.isError, isFalse);
      expect(port.content, 'neu');
      expect(o.summary, 'Kopiert: neu');
      expect(o.undo!.label, 'Zwischenablage wiederherstellen');
      await o.undo!();
      expect(port.content, 'alt');
    });

    test('Undo bei vorher leerer Zwischenablage leert sie', () async {
      port.content = null;
      final o = await tool('clipboard__write').execute({'text': 'neu'}, ctx());
      await o.undo!();
      expect(port.content, '');
    });

    test('Leerraum im Text bleibt erhalten', () async {
      await tool('clipboard__write').execute({'text': '  a\n'}, ctx());
      expect(port.content, '  a\n');
    });

    test('alter Inhalt nicht lesbar: schreibt trotzdem, ohne Undo', () async {
      port.foreground = false;
      final o = await tool('clipboard__write').execute({'text': 'neu'}, ctx());
      expect(o.isError, isFalse);
      expect(port.content, 'neu');
      expect(o.undo, isNull);
    });

    test('undoReadsPrevious: false liest nicht und bietet kein Undo', () async {
      integration = ClipboardIntegration(port, undoReadsPrevious: false);
      final o = await tool('clipboard__write').execute({'text': 'neu'}, ctx());
      expect(o.isError, isFalse);
      expect(o.undo, isNull);
      expect(port.methodCalls, ['write']);
      expect(port.content, 'neu');
    });

    test('Standard liest den alten Inhalt vor dem Schreiben', () async {
      await tool('clipboard__write').execute({'text': 'neu'}, ctx());
      expect(port.methodCalls, ['read', 'write']);
    });

    test('Port-Fehler beim Schreiben', () async {
      port.failNext('write');
      final o = await tool('clipboard__write').execute({'text': 'neu'}, ctx());
      expect(o.isError, isTrue);
      expect(port.content, 'alt');
    });

    test('ungültige Argumente', () async {
      for (final args in [
        <String, Object?>{},
        {'text': ''},
        {'text': 5},
        {'text': 'x' * (ClipboardWriteTool.maxChars + 1)},
      ]) {
        final o = await tool('clipboard__write').execute(args, ctx());
        expect(o.isError, isTrue, reason: args.keys.join());
        expect(o.text, startsWith('Ungültige Argumente'));
      }
      expect(port.content, 'alt');
    });

    test('Bestätigungstext', () {
      final t = tool('clipboard__write');
      expect(
        t.describeForConfirmation({'text': 'Hallo'}),
        'In Zwischenablage kopieren: Hallo',
      );
      expect(
        t.describeForConfirmation({'text': 'a' * 100}),
        'In Zwischenablage kopieren: ${'a' * 59}…',
      );
      expect(t.describeForConfirmation({}), 'In Zwischenablage kopieren');
    });
  });
}
