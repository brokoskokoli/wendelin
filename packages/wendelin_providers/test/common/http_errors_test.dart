import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/src/common/http_errors.dart';
import 'package:wendelin_providers/src/common/json_util.dart';

void main() {
  group('exceptionForStatus', () {
    for (final (status, type, retryable) in [
      (400, InvalidRequestException, false),
      (401, AuthException, false),
      (402, AuthException, false),
      (403, AuthException, false),
      (404, InvalidRequestException, false),
      (408, ProviderTimeoutException, true),
      (413, InvalidRequestException, false),
      (422, InvalidRequestException, false),
      (429, RateLimitException, true),
      (499, InvalidRequestException, false),
      (500, ServerException, true),
      (502, ServerException, true),
      (503, ServerException, true),
      (504, ProviderTimeoutException, true),
      (529, ServerException, true),
      (302, ServerException, false),
    ]) {
      test('$status → $type', () {
        final e = exceptionForStatus(status, label: 'X', detail: 'd');
        expect(e.runtimeType, type);
        expect(e.retryable, retryable);
        expect(e.message, 'X: HTTP $status – d');
      });
    }

    test('ohne Detail, mit retryAfter', () {
      final e = exceptionForStatus(
        429,
        label: 'X',
        retryAfter: const Duration(seconds: 5),
      );
      expect(e.message, 'X: HTTP 429');
      expect((e as RateLimitException).retryAfter, const Duration(seconds: 5));
      expect(
        (exceptionForStatus(529, label: 'X') as ServerException).statusCode,
        529,
      );
    });
  });

  group('exceptionForError', () {
    test('Zuordnung', () {
      const original = AuthException('a');
      expect(exceptionForError(original, label: 'X'), same(original));
      expect(
        exceptionForError(TimeoutException('t'), label: 'X'),
        isA<ProviderTimeoutException>(),
      );
      expect(
        exceptionForError(const FormatException('f'), label: 'X'),
        isA<MalformedResponseException>(),
      );
      final net = exceptionForError(
        http.ClientException('refused'),
        label: 'X',
      );
      expect(net, isA<NetworkException>());
      expect(net.message, contains('refused'));
      expect(
        exceptionForError(StateError('s'), label: 'X'),
        isA<NetworkException>(),
      );
    });
  });

  group('parseRetryAfter', () {
    final now = DateTime.utc(2026, 10, 13, 12);
    test('Sekunden, Millisekunden, Datum, Unsinn', () {
      expect(
        parseRetryAfter({'retry-after': '20'}, now),
        const Duration(seconds: 20),
      );
      expect(
        parseRetryAfter({'retry-after': '1.5'}, now),
        const Duration(milliseconds: 1500),
      );
      expect(
        parseRetryAfter({'retry-after-ms': '250', 'retry-after': '20'}, now),
        const Duration(milliseconds: 250),
      );
      expect(
        parseRetryAfter({'retry-after': 'Tue, 13 Oct 2026 12:00:30 GMT'}, now),
        const Duration(seconds: 30),
      );
      expect(
        parseRetryAfter({'retry-after': 'Tue, 13 Oct 2026 11:00:00 GMT'}, now),
        Duration.zero,
      );
      expect(
        parseRetryAfter({'retry-after': 'Tue, 13 Xyz 2026 11:00:00 GMT'}, now),
        isNull,
      );
      expect(parseRetryAfter({'retry-after': 'bald'}, now), isNull);
      expect(parseRetryAfter({'retry-after': '-3'}, now), isNull);
      expect(parseRetryAfter({'retry-after': ''}, now), isNull);
      expect(parseRetryAfter({'retry-after-ms': '-1'}, now), isNull);
      expect(parseRetryAfter({}, now), isNull);
    });
  });

  group('errorDetail', () {
    test('verschiedene Fehlerformen', () {
      expect(errorDetail('{"error":{"message":"m1"}}'), 'm1');
      expect(errorDetail('{"error":"m2"}'), 'm2');
      expect(errorDetail('{"message":"m3"}'), 'm3');
      expect(errorDetail('{"detail":"m4"}'), 'm4');
      expect(errorDetail('  roher Text  '), 'roher Text');
      expect(errorDetail('{"anders":1}'), '{"anders":1}');
      final long = 'x' * 400;
      expect(errorDetail(long), hasLength(301));
    });
  });
}
