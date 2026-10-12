import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// Receives debug log lines. Lines never contain headers or secrets.
typedef ProviderLog = void Function(String line);

/// Transport settings shared by the HTTP adapters.
@immutable
final class HttpSettings {
  /// Creates settings.
  const HttpSettings({
    this.responseTimeout = const Duration(seconds: 60),
    this.idleTimeout = const Duration(seconds: 120),
    this.clock = const SystemClock(),
    this.log,
  });

  /// Maximum wait for the response headers.
  final Duration responseTimeout;

  /// Maximum silence between two chunks of a streaming body.
  final Duration idleTimeout;

  /// Time source (health-check latency, `retry-after` dates).
  final Clock clock;

  /// Optional debug log.
  final ProviderLog? log;
}

/// Creates the default HTTP client (overridable for tests).
http.Client defaultHttpClient() => http.Client();
