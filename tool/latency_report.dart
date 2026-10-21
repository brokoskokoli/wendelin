// Latenz-Auswertung (WP120): logcat-Zeilen `Wendelin/voice: latency ...` in
// eine Tabelle p50/p90 je Abschnitt.
//
//   adb logcat -d -s flutter | dart run tool/latency_report.dart
//   dart run tool/latency_report.dart log.txt
import 'dart:convert';
import 'dart:io';

import 'src/latency_report.dart';

Future<void> main(List<String> args) async {
  final log = args.isEmpty
      ? await stdin.transform(utf8.decoder).join()
      : File(args.first).readAsStringSync();
  stdout.writeln(latencyReport(log));
}
