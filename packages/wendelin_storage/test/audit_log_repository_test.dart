import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'support/storage_fixture.dart';

void main() {
  group('redactSecrets', () {
    test('ersetzt Secret-Schlüssel rekursiv, behält Zähler', () {
      final input = {
        'api_key': 'k-1',
        'X-Api-Key': 'k-2',
        'apiKey': 'k-3',
        'Authorization': 'Bearer abc',
        'token': 'tok',
        'access_token': 'tok',
        'refreshToken': 'tok',
        'x-auth-token': 'tok',
        'password': 'pw',
        'userPassword': 'pw',
        'Passwort': 'pw',
        'client_secret': 's',
        'Cookie': 'c=1',
        'headers': {
          'authorization': 'Bearer xyz',
          'content-type': 'application/json',
        },
        'calls': [
          {'name': 'x__y', 'token': 'tok'},
          'unverändert',
        ],
        'inputTokens': 120,
        'outputTokens': 5,
        'max_tokens': 1024,
        'tokens': ['a', 'b'],
        'token_present': true,
        'password_hint': null,
        'tokenizer': 'cl100k',
        'transcript': 'Trag mir morgen Tauchen ein',
      };
      expect(redactSecrets(input), {
        'api_key': '***',
        'X-Api-Key': '***',
        'apiKey': '***',
        'Authorization': '***',
        'token': '***',
        'access_token': '***',
        'refreshToken': '***',
        'x-auth-token': '***',
        'password': '***',
        'userPassword': '***',
        'Passwort': '***',
        'client_secret': '***',
        'Cookie': '***',
        'headers': {'authorization': '***', 'content-type': 'application/json'},
        'calls': [
          {'name': 'x__y', 'token': '***'},
          'unverändert',
        ],
        'inputTokens': 120,
        'outputTokens': 5,
        'max_tokens': 1024,
        'tokens': '***',
        'token_present': true,
        'password_hint': null,
        'tokenizer': 'cl100k',
        'transcript': 'Trag mir morgen Tauchen ein',
      });
    });

    test('ganze Objekte unter Secret-Schlüsseln werden ersetzt', () {
      expect(
        redactSecrets({
          'authorization': {'scheme': 'Bearer', 'value': 'abc'},
        }),
        {'authorization': '***'},
      );
      expect(redactSecrets('x'), 'x');
      expect(redactSecrets(3), 3);
    });

    test(
      'Regression: Zahlen/Booleans unter Credential-Schlüsseln werden ersetzt',
      () {
        expect(redactSecrets({'password': 123456, 'apiKey': 42}), {
          'password': '***',
          'apiKey': '***',
        });
        expect(redactSecrets({'pin_secret': true, 'auth': 1, 'key': 7}), {
          'pin_secret': '***',
          'auth': '***',
          'key': '***',
        });
        // Nur token(s)-Schlüssel behalten Zahlen (Zähler).
        expect(redactSecrets({'inputTokens': 3, 'token': 3}), {
          'inputTokens': 3,
          'token': 3,
        });
      },
    );

    test('weitere Credential-Schlüssel', () {
      for (final key in [
        'credential',
        'credentials',
        'privateKey',
        'private_key',
        'bearer',
        'bearerToken',
        'Auth',
        'KEY',
        'passwd',
      ]) {
        expect(redactSecrets({key: 'geheim'}), {key: '***'}, reason: key);
      }
      for (final key in ['keyword', 'author', 'monkey', 'authority']) {
        expect(redactSecrets({key: 'x'}), {key: 'x'}, reason: key);
      }
    });

    test('Name/Wert-Paare', () {
      expect(
        redactSecrets({
          'headers': [
            {'name': 'Authorization', 'value': 'Bearer abc'},
            {'name': 'Accept', 'value': 'text/plain'},
            {'header': 'x-api-key', 'value': 'k'},
          ],
        }),
        {
          'headers': [
            {'name': 'Authorization', 'value': '***'},
            {'name': 'Accept', 'value': 'text/plain'},
            {'header': 'x-api-key', 'value': '***'},
          ],
        },
      );
    });

    test('wertbasiert: Bearer, sk-Schlüssel, Query-Parameter', () {
      expect(
        redactSecrets({
          'log': 'Header Authorization: Bearer eyJabc.def sonst nichts',
          'basic': 'basic dXNlcjpwYXNz',
          'error': 'ungültiger Schlüssel sk-test-ABCDEFGHIJKLMNOP_qrs',
          'kurz': 'sk-kurz',
          'url': 'https://x.example/v1?model=a&api_key=geheim&key=k2#frag',
          'url2': 'https://x.example/?token=t&foo=bar&monkey=1',
          'list': ['Bearer xyz', 3],
        }),
        {
          'log': 'Header Authorization: Bearer *** sonst nichts',
          'basic': 'basic ***',
          'error': 'ungültiger Schlüssel ***',
          'kurz': 'sk-kurz',
          'url': 'https://x.example/v1?model=a&api_key=***&key=***#frag',
          'url2': 'https://x.example/?token=***&foo=bar&monkey=1',
          'list': ['Bearer ***', 3],
        },
      );
      expect(redactSecretValues('nichts Geheimes'), 'nichts Geheimes');
    });

    test('shouldRedactField', () {
      expect(shouldRedactField('password', null), isFalse);
      expect(shouldRedactField('password', 1), isTrue);
      expect(shouldRedactField('outputTokens', 1), isFalse);
      expect(shouldRedactField('accessToken', 'x'), isTrue);
      expect(shouldRedactField('model', 'x'), isFalse);
    });

    test('looksLikeSecretKey', () {
      expect(looksLikeSecretKey('API-KEY'), isTrue);
      expect(looksLikeSecretKey('id_token'), isTrue);
      expect(looksLikeSecretKey('baseUrl'), isFalse);
      expect(looksLikeSecretKey('thinkingBudget'), isFalse);
      expect(looksLikeSecretKey('stopTokenizing'), isFalse);
    });
  });

  group('AuditLogRepository', () {
    late WendelinStorage storage;
    late FixedClock clock;
    late AuditLogRepository repo;

    setUp(() {
      final f = openTestStorage();
      storage = f.storage;
      clock = f.clock;
      repo = storage.audit;
    });
    tearDown(() => storage.close());

    AuditEntry entry(
      Duration ago,
      AuditKind kind, {
      String? session,
      Map<String, Object?> payload = const {},
    }) => AuditEntry(
      at: t0.subtract(ago),
      kind: kind,
      sessionId: session,
      payload: payload,
    );

    test('record redigiert vor dem Speichern', () async {
      final stored = await repo.record(
        entry(
          Duration.zero,
          AuditKind.request,
          session: 's1',
          payload: {
            'transcript': 'Wie wird das Wetter?',
            'headers': {'x-api-key': 'k-secret', 'accept': 'text/event-stream'},
          },
        ),
      );
      expect(stored.id, isNotNull);
      expect(stored.payload['headers'], {
        'x-api-key': '***',
        'accept': 'text/event-stream',
      });
      final read = (await repo.query()).single;
      expect(read, stored);
      expect(read.sessionId, 's1');
      expect(read.at, t0);
      expect(await repo.exportJson(), isNot(contains('k-secret')));
    });

    test(
      'query filtert nach Zeit, Art, Sitzung und Limit, neueste zuerst',
      () async {
        final a = await repo.record(
          entry(const Duration(hours: 3), AuditKind.request, session: 's1'),
        );
        final b = await repo.record(
          entry(const Duration(hours: 2), AuditKind.toolCall, session: 's1'),
        );
        final c = await repo.record(
          entry(const Duration(hours: 1), AuditKind.error, session: 's2'),
        );
        final d = await repo.record(
          entry(const Duration(hours: 1), AuditKind.usage),
        );
        expect(await repo.query(), [d, c, b, a]);
        expect(
          await repo.query(
            AuditFilter(from: t0.subtract(const Duration(hours: 2))),
          ),
          [d, c, b],
        );
        expect(
          await repo.query(
            AuditFilter(until: t0.subtract(const Duration(hours: 2))),
          ),
          [a],
        );
        expect(
          await repo.query(
            const AuditFilter(kinds: {AuditKind.toolCall, AuditKind.error}),
          ),
          [c, b],
        );
        expect(await repo.query(const AuditFilter(sessionId: 's1')), [b, a]);
        expect(await repo.query(const AuditFilter(limit: 2)), [d, c]);
        expect(
          await repo.query(
            const AuditFilter(sessionId: 's1', kinds: {AuditKind.error}),
          ),
          isEmpty,
        );
      },
    );

    test('purgeOlderThan: Standard 30 Tage, Grenze bleibt erhalten', () async {
      await repo.record(entry(const Duration(days: 31), AuditKind.request));
      await repo.record(
        entry(const Duration(days: 30, seconds: 1), AuditKind.request),
      );
      final edge = await repo.record(
        entry(const Duration(days: 30), AuditKind.request),
      );
      final fresh = await repo.record(
        entry(const Duration(days: 1), AuditKind.routing),
      );
      expect(await repo.purgeOlderThan(), 2);
      expect(await repo.query(), [fresh, edge]);
      clock.advance(const Duration(days: 1));
      expect(await repo.purgeOlderThan(const Duration(days: 2)), 1);
      expect(await repo.query(), [fresh]);
      expect(await repo.purgeOlderThan(), 0);
    });

    test('exportJson: JSON-Array, älteste zuerst, alle Felder', () async {
      expect(jsonDecode(await repo.exportJson()), isEmpty);
      await repo.record(
        entry(Duration.zero, AuditKind.usage, payload: {'costMicros': 1500}),
      );
      await repo.record(
        entry(
          const Duration(minutes: 1),
          AuditKind.confirmation,
          session: 's1',
          payload: {'tool': 'calendar__delete_event', 'approved': false},
        ),
      );
      final list = (jsonDecode(await repo.exportJson()) as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(list, hasLength(2));
      expect(list[0], {
        'id': 2,
        'at': t0.subtract(const Duration(minutes: 1)).toUtc().toIso8601String(),
        'kind': 'confirmation',
        'sessionId': 's1',
        'payload': {'tool': 'calendar__delete_event', 'approved': false},
      });
      expect(list[1]['kind'], 'usage');
      expect(list[1]['sessionId'], isNull);
      expect(list[1]['payload'], {'costMicros': 1500});
    });

    test('clear löscht alles', () async {
      await repo.record(entry(Duration.zero, AuditKind.error));
      await repo.clear();
      expect(await repo.query(), isEmpty);
    });

    test('AuditEntry: Gleichheit und Unveränderlichkeit', () {
      final e = AuditEntry(at: t0, kind: AuditKind.error, payload: {'a': 1});
      expect(e, AuditEntry(at: t0, kind: AuditKind.error, payload: {'a': 1}));
      expect(
        e.hashCode,
        AuditEntry(at: t0, kind: AuditKind.error, payload: {'a': 1}).hashCode,
      );
      expect(e, isNot(AuditEntry(at: t0, kind: AuditKind.error)));
      expect(() => e.payload['b'] = 2, throwsUnsupportedError);
      expect(e.toString(), contains('error'));
    });
  });
}
