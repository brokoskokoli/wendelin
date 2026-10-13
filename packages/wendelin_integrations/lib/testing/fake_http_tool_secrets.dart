import '../src/http_tools/http_transport.dart';

/// In-memory [HttpToolSecrets]; records every read reference in [reads]
/// (to prove secrets are read only right before sending). [toString]
/// never shows values.
final class FakeHttpToolSecrets implements HttpToolSecrets {
  /// Creates the fake with [values] (reference → secret).
  FakeHttpToolSecrets([Map<String, String> values = const {}])
    : _values = Map.of(values);

  final Map<String, String> _values;

  /// References read so far, in order.
  final List<String> reads = [];

  /// If set, every read throws it.
  Exception? error;

  /// Stores [value] under [ref].
  void put(String ref, String value) => _values[ref] = value;

  @override
  Future<String?> read(String secretRef) async {
    reads.add(secretRef);
    if (error != null) throw error!;
    return _values[secretRef];
  }

  @override
  String toString() => 'FakeHttpToolSecrets(${_values.keys})';
}
