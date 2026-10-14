import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../support/fake_server.dart';

OpenAiChatAdapter _adapter(FakeServer server) => OpenAiChatAdapter(
  baseUrl: Uri.parse('https://api.openai.com/v1'),
  credentials: Credentials.apiKey('test-key-tap', style: ApiKeyStyle.bearer),
  defaultModel: 'm',
  client: server.client,
);

ChatRequest _request() =>
    ChatRequest(messages: [Message.user('hallo')], model: 'm', maxTokens: 10);

void main() {
  group('Rohbytes des Austauschs (chatObserved)', () {
    test('liefert exakt gesendete und empfangene Bytes vor dem Done', () async {
      final sse = fixture('openai/text.sse');
      final server = FakeServer([FakeResponse.sse(sse, chunkSize: 5)]);
      ExchangeRecord? record;
      final events = <ChatEvent>[];
      await for (final e in _adapter(
        server,
      ).chatObserved(_request(), observer: (r) => record = r)) {
        if (e is Done) expect(record, isNotNull, reason: 'vor dem Done');
        events.add(e);
      }
      expect(events.last, isA<Done>());
      final r = record!;
      expect(r.completed, isTrue);
      expect(r.status, 200);
      expect(utf8.decode(r.responseBytes), sse);
      expect(utf8.decode(r.requestBytes), server.requests.single.body);
    });

    test('Wiederholung ersetzt die Bytes des ersten Versuchs', () async {
      final server = FakeServer([
        FakeResponse.json(400, fixture('openai/400_stream_options.json')),
        FakeResponse.sse(fixture('openai/text.sse')),
      ]);
      ExchangeRecord? record;
      await _adapter(server)
          .chatObserved(_request(), observer: (r) => record = r)
          .toList();
      expect(server.requests, hasLength(2));
      expect(utf8.decode(record!.requestBytes), server.requests.last.body);
      expect(
        utf8.decode(record!.requestBytes),
        isNot(contains('stream_options')),
      );
      expect(utf8.decode(record!.responseBytes), fixture('openai/text.sse'));
    });

    test('Fehler: completed ist false, Quelle meldet nur einmal', () async {
      final server = FakeServer([
        FakeResponse.json(500, fixture('openai/500.json')),
      ]);
      final records = <ExchangeRecord>[];
      final events = await _adapter(server)
          .chatObserved(_request(), observer: records.add)
          .toList();
      expect(events.last, isA<ErrorEvent>());
      expect(records, hasLength(1));
      expect(records.single.completed, isFalse);
      expect(records.single.status, 500);
    });

    test('ohne Beobachter ändert sich nichts', () async {
      final server = FakeServer([FakeResponse.sse(fixture('openai/text.sse'))]);
      final events = await _adapter(server).chat(_request()).toList();
      expect(events.last, isA<Done>());
    });
  });
}
