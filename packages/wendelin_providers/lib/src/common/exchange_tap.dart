import 'dart:typed_data';

/// The raw bytes of one finished HTTP exchange, for checks that must see
/// exactly what went over the wire (TEE receipts, WP46). No wire-format
/// types: only bytes, status and headers.
final class ExchangeRecord {
  /// Creates a record.
  ExchangeRecord({
    required this.requestBytes,
    required this.status,
    required this.responseHeaders,
    required this.responseBytes,
    required this.completed,
  });

  /// The request body exactly as sent.
  final Uint8List requestBytes;

  /// HTTP status, or `null` if no response head arrived.
  final int? status;

  /// Response headers (lower-case names).
  final Map<String, String> responseHeaders;

  /// The response body exactly as received (all chunks, undecoded SSE).
  final Uint8List responseBytes;

  /// The body ended normally (a terminal `Done`), not by error or abort.
  final bool completed;
}

/// Receives the [ExchangeRecord] of a chat call when it ends.
typedef ExchangeObserver = void Function(ExchangeRecord record);

/// Collects the bytes of one chat call for the transport. A retried attempt
/// replaces the data of the earlier one.
final class ExchangeTap {
  /// Creates a tap that reports to [observer] once.
  ExchangeTap(this.observer);

  /// The receiver of the finished record.
  final ExchangeObserver observer;

  Uint8List _request = Uint8List(0);
  int? _status;
  Map<String, String> _headers = const {};
  final BytesBuilder _body = BytesBuilder(copy: false);
  bool _done = false;

  /// A new attempt starts with [bytes] as request body.
  void request(Uint8List bytes) {
    _request = bytes;
    _status = null;
    _headers = const {};
    _body.clear();
  }

  /// The response head arrived.
  void head(int status, Map<String, String> headers) {
    _status = status;
    _headers = {for (final e in headers.entries) e.key.toLowerCase(): e.value};
  }

  /// A body chunk arrived.
  void chunk(List<int> bytes) => _body.add(bytes);

  /// The call ended; reports once.
  void end({required bool completed}) {
    if (_done) return;
    _done = true;
    observer(
      ExchangeRecord(
        requestBytes: _request,
        status: _status,
        responseHeaders: _headers,
        responseBytes: _body.takeBytes(),
        completed: completed,
      ),
    );
  }
}
