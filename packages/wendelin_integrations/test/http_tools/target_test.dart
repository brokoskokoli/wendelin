import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// Resolver with fixed answers; unknown names fail like DNS.
Future<List<InternetAddress>> fakeDns(String host) async => switch (host) {
  'api.example.org' => [InternetAddress('93.184.216.34')],
  'v6.example.org' => [InternetAddress('2606:2800:220:1::1')],
  'rebind.example.org' => [InternetAddress('192.168.178.20')],
  'rebind6.example.org' => [InternetAddress('fd7a:115c:a1e0::1')],
  'loop.example.org' || 'localhost' => [InternetAddress('127.0.0.1')],
  'meta.example.org' => [InternetAddress('169.254.169.254')],
  'mixed.example.org' => [
    InternetAddress('93.184.216.34'),
    InternetAddress('10.0.0.5'),
  ],
  'mapped.example.org' => [InternetAddress('::ffff:10.0.0.5')],
  'zero.example.org' => [InternetAddress('0.0.0.0')],
  'ha.local' => [InternetAddress('192.168.178.20')],
  'homeserver.tail1234.ts.net' => [InternetAddress('100.101.102.103')],
  'nas.example.org' => [InternetAddress('192.168.178.30')],
  'public.lan' => [InternetAddress('93.184.216.34')],
  'leer.example.org' => <InternetAddress>[],
  _ => throw const SocketException('NXDOMAIN'),
};

Future<HttpTarget> check(
  String url, {
  bool home = false,
  bool testMode = false,
}) => checkHttpTarget(
  Uri.parse(url),
  homeNetwork: home,
  resolve: fakeDns,
  allowLoopback: testMode,
);

Matcher rejected([String? text]) => throwsA(
  isA<PortException>()
      .having((e) => e.kind, 'kind', PortErrorKind.rejected)
      .having(
        (e) => e.message,
        'message',
        text == null ? startsWith('Ziel nicht erlaubt') : contains(text),
      ),
);

void main() {
  group('Zielprüfung: erlaubt', () {
    final allowed = <String, ({String url, bool home})>{
      'https öffentlich': (url: 'https://api.example.org/x', home: false),
      'https IPv6 öffentlich': (url: 'https://v6.example.org/', home: false),
      'öffentliche IP-Literal https': (
        url: 'https://93.184.216.34/',
        home: false,
      ),
      'LAN-IP mit http': (url: 'http://192.168.178.20:8123/api', home: false),
      '10.0.2.2 (Emulator-Host) mit http': (
        url: 'http://10.0.2.2:8080/',
        home: false,
      ),
      'Tailscale-IP mit http': (url: 'http://100.101.102.103/', home: false),
      'ULA-IPv6 mit http': (url: 'http://[fd7a:115c:a1e0::1]/', home: false),
      '.local löst privat auf': (url: 'http://ha.local:8123/', home: false),
      '*.ts.net löst auf Tailscale auf': (
        url: 'https://homeserver.tail1234.ts.net/hook',
        home: false,
      ),
      'als Heimnetz markierter Name löst privat auf': (
        url: 'http://nas.example.org/',
        home: true,
      ),
      'Heimnetz-Name, der öffentlich auflöst, mit https': (
        url: 'https://public.lan/',
        home: false,
      ),
    };
    for (final MapEntry(key: name, value: c) in allowed.entries) {
      test(name, () async {
        final t = await check(c.url, home: c.home);
        expect(t.origin, Uri.parse(Uri.parse(c.url).origin));
        expect(t.addresses, isNotEmpty);
      });
    }
  });

  group('Zielprüfung: abgelehnt', () {
    final blocked = <String, ({String url, bool home, String? why})>{
      'DNS-Rebinding: öffentlicher Name → LAN': (
        url: 'https://rebind.example.org/',
        home: false,
        why: 'private Netz',
      ),
      'DNS-Rebinding: öffentlicher Name → ULA': (
        url: 'https://rebind6.example.org/',
        home: false,
        why: 'private Netz',
      ),
      'DNS-Rebinding: eine von mehreren Adressen privat': (
        url: 'https://mixed.example.org/',
        home: false,
        why: 'private Netz',
      ),
      'DNS-Rebinding: IPv4-mapped privat': (
        url: 'https://mapped.example.org/',
        home: false,
        why: 'private Netz',
      ),
      'Name → Loopback (auch als Heimnetz)': (
        url: 'https://loop.example.org/',
        home: true,
        why: 'Gerät selbst',
      ),
      'Name → Cloud-Metadaten (Link-Local)': (
        url: 'http://meta.example.org/',
        home: true,
        why: 'Link-Local',
      ),
      'Name → 0.0.0.0': (
        url: 'https://zero.example.org/',
        home: true,
        why: 'keine gültige Zieladresse',
      ),
      '127.0.0.1': (url: 'http://127.0.0.1/', home: true, why: null),
      '127.8.9.10': (url: 'http://127.8.9.10/', home: true, why: null),
      '::1': (url: 'http://[::1]/', home: true, why: null),
      '::ffff:127.0.0.1': (
        url: 'http://[::ffff:127.0.0.1]/',
        home: true,
        why: null,
      ),
      '169.254.169.254': (
        url: 'http://169.254.169.254/',
        home: true,
        why: null,
      ),
      'fe80::1': (url: 'http://[fe80::1]/', home: true, why: null),
      'fe80 mit Zone': (url: 'http://[fe80::1%25eth0]/', home: true, why: null),
      '0.0.0.0': (url: 'http://0.0.0.0/', home: true, why: null),
      '[::]': (url: 'http://[::]/', home: true, why: null),
      'Multicast': (url: 'http://224.0.0.1/', home: true, why: null),
      'Broadcast': (url: 'http://255.255.255.255/', home: true, why: null),
      'NAT64 auf Loopback': (
        url: 'http://[64:ff9b::7f00:1]/',
        home: true,
        why: null,
      ),
      '6to4 auf Loopback': (
        url: 'http://[2002:7f00:1::]/',
        home: true,
        why: null,
      ),
      'localhost': (url: 'http://localhost:8080/', home: true, why: 'lokales'),
      'api.localhost': (
        url: 'http://api.localhost/',
        home: true,
        why: 'lokales',
      ),
      'dezimal 2130706433': (
        url: 'http://2130706433/',
        home: true,
        why: 'IP-Schreibweise',
      ),
      'hex 0x7f000001': (
        url: 'http://0x7f000001/',
        home: true,
        why: 'IP-Schreibweise',
      ),
      'gemischt 0x7f.1': (
        url: 'http://0x7f.1/',
        home: true,
        why: 'IP-Schreibweise',
      ),
      'kurz 127.1': (url: 'http://127.1/', home: true, why: 'IP-Schreibweise'),
      'oktal 0177.0.0.1': (
        url: 'http://0177.0.0.1/',
        home: true,
        why: 'IP-Schreibweise',
      ),
      'führende Null 010.0.0.1': (
        url: 'http://010.0.0.1/',
        home: true,
        why: 'IP-Schreibweise',
      ),
      'http öffentlich': (
        url: 'http://api.example.org/',
        home: false,
        why: '„http“ nur im Heimnetz',
      ),
      'http öffentliches IP-Literal': (
        url: 'http://93.184.216.34/',
        home: false,
        why: '„http“ nur im Heimnetz',
      ),
      'http, Heimnetz markiert, aber öffentliche Adresse': (
        url: 'http://api.example.org/',
        home: true,
        why: 'öffentlich erreichbar',
      ),
      'http, .lan-Name mit öffentlicher Adresse': (
        url: 'http://public.lan/',
        home: false,
        why: 'öffentlich erreichbar',
      ),
      'Zugangsdaten in der URL': (
        url: 'https://u:p@api.example.org/',
        home: false,
        why: 'Zugangsdaten',
      ),
      'ftp': (url: 'ftp://api.example.org/', home: false, why: 'nur http'),
      'file': (url: 'file:///etc/passwd', home: true, why: 'nur http'),
    };
    for (final MapEntry(key: name, value: c) in blocked.entries) {
      test(name, () async {
        await expectLater(check(c.url, home: c.home), rejected(c.why));
      });
    }

    test('unbekannter Host → nicht erreichbar, nicht abgelehnt', () async {
      for (final url in ['https://gibts.nicht/', 'https://leer.example.org/']) {
        await expectLater(
          check(url),
          throwsA(
            isA<PortException>().having(
              (e) => e.kind,
              'kind',
              PortErrorKind.unavailable,
            ),
          ),
        );
      }
    });
  });

  group('Test-Modus (allowLoopback)', () {
    test('Loopback und Link-Local erlaubt, wenn Heimnetz', () async {
      await check('http://127.0.0.1:9000/', testMode: true);
      await check('http://[::1]:9000/', home: true, testMode: true);
      await check('http://loop.example.org/', home: true, testMode: true);
      await check('http://localhost:9000/', home: true, testMode: true);
    });

    test('öffentlicher Name auf Loopback bleibt verboten', () async {
      await expectLater(
        check('https://loop.example.org/', testMode: true),
        rejected('lokale Netz'),
      );
    });

    test('0.0.0.0 bleibt verboten', () async {
      await expectLater(
        check('http://0.0.0.0/', home: true, testMode: true),
        rejected(),
      );
    });
  });

  group('Adressklassen', () {
    final cases = <String, AddressScope>{
      '8.8.8.8': AddressScope.public,
      '172.15.0.1': AddressScope.public,
      '172.16.0.1': AddressScope.private,
      '172.31.255.255': AddressScope.private,
      '172.32.0.1': AddressScope.public,
      '100.63.255.255': AddressScope.public,
      '100.64.0.1': AddressScope.private,
      '100.127.255.255': AddressScope.private,
      '100.128.0.1': AddressScope.public,
      '192.0.0.8': AddressScope.blocked,
      '198.18.0.1': AddressScope.blocked,
      '2001:4860:4860::8888': AddressScope.public,
      'fc00::1': AddressScope.private,
      'fec0::1': AddressScope.private,
      'ff02::1': AddressScope.blocked,
      '::10.0.0.1': AddressScope.private,
      '64:ff9b::808:808': AddressScope.public,
      '2002:c0a8:101::': AddressScope.private,
    };
    for (final MapEntry(key: ip, value: scope) in cases.entries) {
      test('$ip → ${scope.name}', () {
        expect(classifyAddress(InternetAddress(ip)), scope);
      });
    }

    test('Heimnetz-Namen', () {
      expect(isHomeNetworkHost('ha.local.'), isTrue);
      expect(isHomeNetworkHost('router.home.arpa'), isTrue);
      expect(isHomeNetworkHost('x.tail1234.ts.net'), isTrue);
      expect(isHomeNetworkHost('10.0.2.2'), isTrue);
      expect(isHomeNetworkHost('127.0.0.1'), isFalse);
      expect(isHomeNetworkHost('example.org'), isFalse);
      expect(isHomeNetworkHost('local.example.org'), isFalse);
    });

    test('gleicher Origin', () async {
      final t = await check('https://api.example.org/a');
      expect(t.sameOrigin(Uri.parse('https://api.example.org/b?x')), isTrue);
      expect(t.sameOrigin(Uri.parse('https://API.example.org./b')), isTrue);
      expect(t.sameOrigin(Uri.parse('http://api.example.org/b')), isFalse);
      expect(t.sameOrigin(Uri.parse('https://api.example.org:444/')), isFalse);
      expect(t.sameOrigin(Uri.parse('https://evil.example/')), isFalse);
      expect(t.sameOrigin(Uri.parse('https://u@api.example.org/')), isFalse);
      expect(t.toString(), contains('api.example.org'));
    });
  });
}
