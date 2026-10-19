// WP41: HTTP tools (user-defined) are never trusted content sources. The
// per-integration trust table for the built-in tools lives in the app tests
// (`app/test/trust/<id>.json`, checked by `app/test/di/trust_registry_test.dart`).
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'http_tools/support.dart' as http_support;

void main() {
  test('HTTP-Tools sind nie vertrauenswürdig', () {
    final h = http_support.mockRunner((_) async => http.Response('', 200));
    final tool = HttpTool(http_support.def(), h.runner);
    expect(tool, isNot(isA<TrustedContentSource>()));
  });
}
