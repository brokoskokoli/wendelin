// Kopie der Parser-Tests aus wendelin_providers (Parser liegt seit WP22 in
// core); die Provider-Tests laufen dort unverändert weiter.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';

Future<List<SseEvent>> parseChunks(List<List<int>> chunks) =>
    SseParser.parse(Stream.fromIterable(chunks)).toList();

Future<List<SseEvent>> parseText(String text) =>
    parseChunks([utf8.encode(text)]);

/// Splits [bytes] at random positions (possibly inside UTF-8 sequences and
/// between `\r` and `\n`).
List<List<int>> randomSplit(List<int> bytes, Random random) {
  final chunks = <List<int>>[];
  var i = 0;
  while (i < bytes.length) {
    final size = 1 + random.nextInt(min(12, bytes.length - i));
    chunks.add(bytes.sublist(i, i + size));
    i += size;
  }
  return chunks;
}

void main() {
  group('SseParser', () {
    test('event, data, id und Leerzeile trennen Events', () async {
      final events = await parseText(
        'event: ping\ndata: {"a":1}\nid: 7\n\ndata: zwei\n\n',
      );
      expect(events, [
        const SseEvent(event: 'ping', data: '{"a":1}', id: '7'),
        const SseEvent(data: 'zwei', id: '7'),
      ]);
    });

    test('mehrzeilige data werden mit \\n verbunden', () async {
      final events = await parseText('data: eins\ndata: zwei\ndata:\n\n');
      expect(events.single.data, 'eins\nzwei\n');
    });

    test('Kommentarzeilen und unbekannte Felder werden ignoriert', () async {
      final events = await parseText(
        ': keep-alive\nretry: 100\nfoo: bar\ndata: x\n\n',
      );
      expect(events, [const SseEvent(data: 'x')]);
    });

    test(
      'Events ohne data werden verworfen, event-Typ zurückgesetzt',
      () async {
        final events = await parseText('event: leer\n\ndata: x\n\n');
        expect(events, [const SseEvent(data: 'x')]);
      },
    );

    test('nur ein Leerzeichen nach dem Doppelpunkt wird entfernt', () async {
      final events = await parseText('data:ohne\n\ndata:  zwei\n\ndata\n\n');
      expect(events.map((e) => e.data), ['ohne', ' zwei', '']);
    });

    test('\\r\\n und \\r als Zeilenende', () async {
      final events = await parseText('data: a\r\n\r\ndata: b\r\rdata: c\n\n');
      expect(events.map((e) => e.data), ['a', 'b', 'c']);
    });

    test('BOM am Anfang wird entfernt', () async {
      final events = await parseText('﻿data: x\n\n');
      expect(events.single.data, 'x');
    });

    test('id mit NUL wird ignoriert', () async {
      final events = await parseText(
        'id: 1\ndata: a\n\nid: b\u0000\ndata: c\n\n',
      );
      expect(events.map((e) => e.id), ['1', '1']);
    });

    test('[DONE] wird erkannt', () async {
      final events = await parseText('data: [DONE]\n\n');
      expect(events.single.isDone, isTrue);
      expect(const SseEvent(data: '[DONE] ').isDone, isFalse);
    });

    test('offenes Event am Stream-Ende wird noch geliefert', () async {
      final events = await parseText('data: a\n\ndata: b');
      expect(events.map((e) => e.data), ['a', 'b']);
    });

    test('UTF-8-Zeichen über Chunk-Grenzen', () async {
      final bytes = utf8.encode('data: Grüße 🦊\n\n');
      final split = bytes.indexOf(0xF0) + 2; // mitten im Emoji
      final events = await parseChunks([
        bytes.sublist(0, split),
        bytes.sublist(split),
      ]);
      expect(events.single.data, 'Grüße 🦊');
    });

    test('\\r und \\n in verschiedenen Chunks sind ein Zeilenende', () async {
      final events = await parseChunks([
        utf8.encode('data: a\r'),
        utf8.encode('\n\r'),
        utf8.encode('\ndata: b\n\n'),
      ]);
      expect(events.map((e) => e.data), ['a', 'b']);
    });

    test('ungültiges UTF-8 endet mit FormatException', () {
      expect(
        parseChunks([
          [0x64, 0x61, 0x74, 0x61, 0x3A, 0xFF, 0x0A, 0x0A],
        ]),
        throwsFormatException,
      );
    });

    test('Gleichheit und toString', () {
      const a = SseEvent(data: 'x', event: 'e', id: '1');
      expect(a, const SseEvent(data: 'x', event: 'e', id: '1'));
      expect(
        a.hashCode,
        const SseEvent(data: 'x', event: 'e', id: '1').hashCode,
      );
      expect(a, isNot(const SseEvent(data: 'x', event: 'f', id: '1')));
      expect(a.toString(), contains('data: x'));
    });

    test(
      'Abbruch kündigt die Quelle sofort (auch ohne weitere Daten)',
      () async {
        var cancelled = false;
        final source = StreamController<List<int>>(
          onCancel: () => cancelled = true,
        )..add(utf8.encode('data: a\n\n'));
        final sub = SseParser.parse(source.stream).listen(null);
        await pumpEventQueue();
        await sub.cancel();
        expect(cancelled, isTrue);
        await source.close();
      },
    );

    group('Property: beliebige Zerstückelung ergibt dieselben Events', () {
      final inputs = {
        'mehrere Ereignisse':
            'event: message\ndata: {"jsonrpc":"2.0","id":1}\n\n'
            'event: endpoint\ndata: /messages?sessionId=ä1\n\n'
            'id: 3\ndata: {"a":\ndata: "b"}\n\n',
        'synthetisch':
            'event: x\r\ndata: Grüße 🦊\r\ndata: zweite\r\n\r\n'
            ': kommentar\rdata: ä\r\rid: 9\ndata: [DONE]\n\n',
      };
      for (final MapEntry(key: name, value: text) in inputs.entries) {
        test(name, () async {
          final bytes = utf8.encode(text);
          final expected = await parseChunks([bytes]);
          expect(expected, isNotEmpty);
          final random = Random(name.hashCode);
          for (var run = 0; run < 200; run++) {
            final chunks = randomSplit(bytes, random);
            expect(
              await parseChunks(chunks),
              expected,
              reason: 'Zerlegung: ${chunks.map((c) => c.length).toList()}',
            );
          }
          // Extremfall: jedes Byte einzeln.
          expect(
            await parseChunks([
              for (final b in bytes) [b],
            ]),
            expected,
          );
        });
      }
    });
  });
}
