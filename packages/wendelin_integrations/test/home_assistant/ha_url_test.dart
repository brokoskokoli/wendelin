import 'package:test/test.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

void main() {
  group('http nur für private Adressen', () {
    for (final host in [
      '10.0.0.5',
      '172.16.1.1',
      '172.31.255.255',
      '192.168.1.20',
      '100.64.0.1',
      '100.127.255.254',
      'homeassistant.local',
      'ha.tailnet-name.ts.net',
      '[fd7a:115c:a1e0::1]',
      '127.0.0.1',
      'localhost',
    ]) {
      test('$host: http erlaubt', () {
        expect(HaUrl.parse('http://$host:8123'), 'http://$host:8123');
      });
    }

    for (final host in [
      '8.8.8.8',
      '172.32.0.1',
      '100.128.0.1',
      '100.63.255.255',
      '192.169.0.1',
      'example.com',
      'homeassistant',
      'evil.local.example.com',
      'ts.net.evil.com',
      '2130706433',
      '0x7f.1',
      '169.254.1.1',
      '[2001:db8::1]',
    ]) {
      test('$host: http abgelehnt', () {
        expect(
          () => HaUrl.parse('http://$host'),
          throwsA(
            isA<PortException>().having(
              (e) => e.kind,
              'kind',
              PortErrorKind.rejected,
            ),
          ),
        );
      });
    }
  });

  test('https ist überall erlaubt', () {
    expect(HaUrl.parse('https://ha.example.com'), 'https://ha.example.com');
  });

  test('ohne Schema: privat → http, sonst https', () {
    expect(HaUrl.parse('192.168.1.5:8123'), 'http://192.168.1.5:8123');
    expect(
      HaUrl.parse('homeassistant.local:8123'),
      'http://homeassistant.local:8123',
    );
    expect(HaUrl.parse('ha.example.com'), 'https://ha.example.com');
  });

  test('Normalisierung und ungültige Eingaben', () {
    expect(HaUrl.parse('  http://10.0.0.1:8123/  '), 'http://10.0.0.1:8123');
    expect(HaUrl.parse('https://x.example/ha/'), 'https://x.example/ha');
    for (final bad in [
      '',
      'ftp://10.0.0.1',
      'http://u:p@10.0.0.1',
      'http://10.0.0.1/?a=1',
      'http://10.0.0.1/#x',
      'http://',
    ]) {
      expect(
        () => HaUrl.parse(bad),
        throwsA(isA<PortException>()),
        reason: bad,
      );
    }
  });

  test('Endpoint zeigt das Token nie', () {
    expect(
      const HaEndpoint(url: 'u', token: 'geheim').toString(),
      isNot(contains('geheim')),
    );
  });
}
