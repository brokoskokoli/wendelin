import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/attest_log.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

void main() {
  late List<String> lines;
  late void Function(String) saved;

  setUp(() {
    lines = [];
    saved = attestLogSink;
    attestLogSink = lines.add;
  });
  tearDown(() => attestLogSink = saved);

  test('nur Wendelin/attest-Zeilen kommen ins Log, keine URLs', () {
    attestLog('Wendelin/attest: receipt receipt.fetch=pass');
    attestLog('OpenAI: GET https://example.test/v1/aci/receipts/rcpt-1');
    expect(lines, ['Wendelin/attest: receipt receipt.fetch=pass']);
  });

  test('attestSettings behält Zeiten und Uhr und schaltet das Log ein', () {
    const base = HttpSettings(responseTimeout: Duration(seconds: 7));
    final s = attestSettings(base);
    expect(s.responseTimeout, const Duration(seconds: 7));
    s.log!('Wendelin/attest: session quote=pass');
    s.log!('x');
    expect(lines, ['Wendelin/attest: session quote=pass']);
    expect(attestSettings(null).log, isNotNull);
  });

  test('ein vorhandenes Log des Transports bekommt weiter alle Zeilen', () {
    final all = <String>[];
    final s = attestSettings(HttpSettings(log: all.add));
    s.log!('x');
    s.log!('Wendelin/attest: receipt red');
    expect(all, ['x', 'Wendelin/attest: receipt red']);
    expect(lines, ['Wendelin/attest: receipt red']);
  });
}
