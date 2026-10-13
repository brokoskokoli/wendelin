@Tags(['live'])
library;

import 'package:test/test.dart';
import 'package:wendelin_integrations/fakes.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

// Live-Test ohne Schlüssel: HTTPS über den Pinning-Transport gegen einen
// öffentlichen Host (Zertifikat wird gegen den Namen geprüft, obwohl die
// Verbindung zur vorab geprüften IP geht). Start:
//   dart test -t live --run-skipped test/live/http_tools_live_test.dart

void main() {
  final runner = HttpToolRunner(
    transport: PinnedHttpToolTransport(),
    secrets: FakeHttpToolSecrets(),
  );

  HttpToolDefinition get(String url) => HttpToolDefinition(
    id: 'live',
    name: 'live',
    description: 'Live-Test',
    method: HttpMethod.get,
    urlTemplate: url,
  );

  test('HTTPS mit gepinnter Adresse', () async {
    final r = await runner.call(get('https://example.com/'), {});
    expect(r.error, isNull);
    expect(r.status, 200);
    expect(r.text, contains('Example Domain'));
  });

  test('falscher Hostname im Zertifikat wird abgelehnt', () async {
    final r = await runner.call(get('https://wrong.host.badssl.com/'), {});
    expect(r.error, contains('nicht erreichbar'));
  });
}
