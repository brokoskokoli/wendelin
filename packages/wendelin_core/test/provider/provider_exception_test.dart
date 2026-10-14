import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';

void main() {
  group('retryable', () {
    final table = <ProviderException, bool>{
      const AuthException('401'): false,
      const RateLimitException('429'): true,
      const RateLimitException('429', retryAfter: Duration(seconds: 3)): true,
      const ProviderTimeoutException('zu langsam'): true,
      const NetworkException('offline'): true,
      const ServerException('überlastet', statusCode: 529): true,
      const ServerException('kaputt', statusCode: 500): true,
      const ServerException('gateway', statusCode: 502): true,
      const ServerException('unerwartet', statusCode: 499): false,
      const ServerException('teapot', statusCode: 418): false,
      const InvalidRequestException('400'): false,
      const CancelledException(): false,
      const MalformedResponseException('kein JSON'): false,
    };
    table.forEach((exception, expected) {
      test('$exception → $expected', () {
        expect(exception.retryable, expected);
      });
    });
  });

  test('is an Exception with readable toString', () {
    const e = AuthException('Schlüssel ungültig');
    expect(e, isA<Exception>());
    expect(e.toString(), 'AuthException: Schlüssel ungültig');
    expect(const CancelledException().message, 'Abgebrochen');
  });

  group('equality', () {
    test('same type and message', () {
      expect(const NetworkException('a'), const NetworkException('a'));
      expect(
        const NetworkException('a').hashCode,
        const NetworkException('a').hashCode,
      );
      expect(const NetworkException('a'), isNot(const NetworkException('b')));
      expect(
        const NetworkException('a'),
        isNot(const ProviderTimeoutException('a')),
      );
    });
    test('RateLimitException compares retryAfter', () {
      const a = RateLimitException('x', retryAfter: Duration(seconds: 1));
      expect(
        a,
        const RateLimitException('x', retryAfter: Duration(seconds: 1)),
      );
      expect(
        a.hashCode,
        const RateLimitException(
          'x',
          retryAfter: Duration(seconds: 1),
        ).hashCode,
      );
      expect(
        a,
        isNot(const RateLimitException('x', retryAfter: Duration(seconds: 2))),
      );
      expect(
        a,
        isNot(const RateLimitException('y', retryAfter: Duration(seconds: 1))),
      );
    });
    test('ServerException compares statusCode', () {
      const a = ServerException('x', statusCode: 500);
      expect(a, const ServerException('x', statusCode: 500));
      expect(a.hashCode, const ServerException('x', statusCode: 500).hashCode);
      expect(a, isNot(const ServerException('x', statusCode: 503)));
      expect(a, isNot(const ServerException('y', statusCode: 500)));
    });
    test('AttestationFailedException: retryable nur wenn nicht prüfbar', () {
      const failed = AttestationFailedException('x', stage: 'quote');
      const offline = AttestationFailedException(
        'x',
        stage: 'quote',
        unavailable: true,
      );
      expect(failed.retryable, isFalse);
      expect(offline.retryable, isTrue);
      expect(failed.stage, 'quote');
      const fallback = AttestationFailedException(
        'x',
        stage: 'quote',
        fallback: true,
      );
      expect(fallback.retryable, isTrue, reason: 'Ausweichen erlaubt');
    });
    test('AttestationReport vergleicht Felder', () {
      const a = AttestationReport(
        logId: 'l',
        status: AttestationStatus.green,
        detail: 'd',
      );
      expect(
        a,
        const AttestationReport(
          logId: 'l',
          status: AttestationStatus.green,
          detail: 'd',
        ),
      );
      expect(
        a,
        isNot(
          const AttestationReport(logId: 'l', status: AttestationStatus.red),
        ),
      );
      expect(a.hashCode, isNot(0));
      expect(
        const AttestationStatusChanged(
          stepId: 's:1',
          status: AttestationStatus.red,
          logId: 'l',
        ).toString(),
        contains('red'),
      );
    });
  });
}
