import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:wendelin_core/wendelin_core.dart';

/// Maps an HTTP error status onto a [ProviderException].
///
/// [label] names the provider, [detail] is the provider's (already
/// extracted) error text. 401/402/403 → auth, 429 → rate limit (with
/// [retryAfter]), 408/504 → timeout, 5xx and 529 → server, other 4xx →
/// invalid request.
ProviderException exceptionForStatus(
  int status, {
  required String label,
  String detail = '',
  Duration? retryAfter,
}) {
  final text = detail.isEmpty
      ? '$label: HTTP $status'
      : '$label: HTTP $status – $detail';
  return switch (status) {
    401 || 402 || 403 => AuthException(text),
    429 => RateLimitException(text, retryAfter: retryAfter),
    408 || 504 => ProviderTimeoutException(text),
    >= 500 => ServerException(text, statusCode: status),
    >= 400 => InvalidRequestException(text),
    _ => ServerException(text, statusCode: status),
  };
}

/// Maps an exception thrown while talking to the server.
ProviderException exceptionForError(Object error, {required String label}) =>
    switch (error) {
      ProviderException() => error,
      TimeoutException() => ProviderTimeoutException(
        '$label: Zeitüberschreitung',
      ),
      FormatException(:final message) => MalformedResponseException(
        '$label: Antwort nicht lesbar ($message)',
      ),
      http.ClientException(:final message) => NetworkException(
        '$label: Verbindung fehlgeschlagen ($message)',
      ),
      _ => NetworkException('$label: Verbindung fehlgeschlagen ($error)'),
    };

/// Reads the wait time from `retry-after-ms` or `retry-after` (seconds or
/// HTTP date relative to [now]); `null` if absent or unreadable.
Duration? parseRetryAfter(Map<String, String> headers, DateTime now) {
  final ms = int.tryParse(headers['retry-after-ms']?.trim() ?? '');
  if (ms != null && ms >= 0) return Duration(milliseconds: ms);
  final raw = headers['retry-after']?.trim();
  if (raw == null || raw.isEmpty) return null;
  final seconds = num.tryParse(raw);
  if (seconds != null) {
    return seconds < 0
        ? null
        : Duration(milliseconds: (seconds * 1000).round());
  }
  final date = _parseHttpDate(raw);
  if (date == null) return null;
  final diff = date.difference(now);
  return diff.isNegative ? Duration.zero : diff;
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Parses an IMF-fixdate such as `Sun, 06 Nov 1994 08:49:37 GMT`.
DateTime? _parseHttpDate(String s) {
  final m = RegExp(
    r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
  ).firstMatch(s);
  if (m == null) return null;
  final month = _months.indexOf(m.group(2)!) + 1;
  if (month == 0) return null;
  return DateTime.utc(
    int.parse(m.group(3)!),
    month,
    int.parse(m.group(1)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6)!),
  );
}
