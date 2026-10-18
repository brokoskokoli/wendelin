import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;
import 'package:wendelin_core/wendelin_core.dart';

import '../common/port_exception.dart';
import '../web/web_search_backend.dart' show sendForJson;

/// User agent for services that require contact data (MET Norway).
String weatherUserAgent(String appVersion) =>
    'Wendelin/$appVersion github.com/brokoskokoli/wendelin';

/// GETs [url] as JSON object; failures become [PortException]s naming
/// [service].
Future<Map<String, Object?>> getJsonObject(
  http.Client client,
  Uri url, {
  required String service,
  Map<String, String> headers = const {},
  CancelToken? cancel,
  Map<int, String> statusMessages = const {},
}) async {
  final request = http.Request('GET', url)
    ..headers.addAll({'Accept': 'application/json', ...headers});
  final json = await sendForJson(
    client,
    request,
    service: service,
    cancel: cancel,
    statusMessages: statusMessages,
  );
  if (json is! Map<String, Object?>) throw badAnswer(service);
  return json;
}

/// Unreadable answer of [service].
PortException badAnswer(String service) =>
    PortException(PortErrorKind.failed, '$service: unerwartete Antwort');

/// [v] as number or `null`.
double? num_(Object? v) => v is num ? v.toDouble() : null;

/// [v] as list (empty if it is not one).
List<Object?> list_(Object? v) => v is List<Object?> ? v : const [];

/// Entry [i] of the list [v] as number or `null` (out of range, not a number).
double? numAt(Object? v, int i) {
  final l = list_(v);
  return i < l.length ? num_(l[i]) : null;
}

/// Parses a local wall time like `2026-10-18T13:00` in [zone].
tz.TZDateTime parseLocal(String text, tz.Location zone) {
  final t = DateTime.tryParse(text);
  if (t == null) throw const FormatException('Zeit');
  return tz.TZDateTime(zone, t.year, t.month, t.day, t.hour, t.minute);
}

/// Parses an instant (with offset or `Z`) and shows it in [zone].
tz.TZDateTime parseInstant(String text, tz.Location zone) {
  final t = DateTime.tryParse(text);
  if (t == null) throw const FormatException('Zeit');
  return tz.TZDateTime.from(t.toUtc(), zone);
}

/// Day rounded to a calendar date (UTC midnight value, no zone).
DateTime dateOf(tz.TZDateTime t) => DateTime.utc(t.year, t.month, t.day);
