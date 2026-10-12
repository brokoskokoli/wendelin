import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:wendelin_evals/wendelin_evals.dart';

/// `dart run wendelin_evals:run --profile <profil.json> [Optionen]`
///
/// Strg+C beendet nach dem laufenden Fall und schreibt den Teilreport; ein
/// zweites Strg+C bricht sofort ab.
Future<void> main(List<String> args) async {
  final client = http.Client();
  final interrupt = StreamController<void>.broadcast();
  var count = 0;
  // Genau ein Abo auf das Signal; es wird am Ende gekündigt, sonst bleibt
  // der Prozess nach dem Lauf hängen.
  final signals = ProcessSignal.sigint.watch().listen((_) {
    if (++count >= 2) exit(130);
    interrupt.add(null);
  });
  try {
    exitCode = await runCli(
      args,
      env: Platform.environment,
      out: stdout,
      err: stderr,
      client: client,
      interrupt: interrupt.stream,
    );
  } finally {
    await signals.cancel();
    await interrupt.close();
    client.close();
  }
}
