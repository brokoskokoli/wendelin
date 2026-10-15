import 'package:flutter/foundation.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

/// Prefix of the TEE check diagnostics in the log (`adb logcat | grep
/// Wendelin/attest`). The lines name the kind, the stage, the outcome and a
/// reason code, never contents, keys or receipts.
const attestLogPrefix = 'Wendelin/attest:';

/// Where the lines go (tests capture them). Release builds print too, like
/// the voice diagnostics, so the maintainer can read them on a phone.
@visibleForTesting
void Function(String line) attestLogSink = debugPrint;

/// Passes only the `Wendelin/attest:` lines of the provider log on: the
/// HTTP layer logs other lines (URLs) into the same sink.
void attestLog(String line) {
  if (line.startsWith(attestLogPrefix)) attestLogSink(line);
}

/// The HTTP settings of the providers: [base] (the test transport) or the
/// defaults, plus the attest log.
HttpSettings attestSettings(HttpSettings? base) {
  final b = base ?? const HttpSettings();
  return HttpSettings(
    responseTimeout: b.responseTimeout,
    idleTimeout: b.idleTimeout,
    clock: b.clock,
    log: b.log == null
        ? attestLog
        : (line) {
            b.log!(line);
            attestLog(line);
          },
  );
}
