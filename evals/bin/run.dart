import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:wendelin_evals/wendelin_evals.dart';

/// `dart run wendelin_evals:run --profile <profil.json> [Optionen]`
Future<void> main(List<String> args) async {
  final client = http.Client();
  try {
    exitCode = await runCli(
      args,
      env: Platform.environment,
      out: stdout,
      err: stderr,
      client: client,
    );
  } finally {
    client.close();
  }
}
