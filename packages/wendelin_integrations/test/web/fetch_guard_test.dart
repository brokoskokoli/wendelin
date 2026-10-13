import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// Resolver with fixed answers; unknown hosts fail like DNS.
Future<List<InternetAddress>> fakeDns(String host) async => switch (host) {
  'example.org' => [InternetAddress('93.184.216.34')],
  'v6.example.org' => [InternetAddress('2606:2800:220:1::1')],
  'rebind.example.org' => [InternetAddress('10.0.0.5')],
  'mixed.example.org' => [
    InternetAddress('93.184.216.34'),
    InternetAddress('127.0.0.1'),
  ],
  'leer.example.org' => <InternetAddress>[],
  _ => throw const SocketException('NXDOMAIN'),
};

Future<void> check(String url, {Set<String> allowed = const {}}) =>
    checkFetchTarget(Uri.parse(url), allowedHosts: allowed, resolve: fakeDns);

void main() {
  final blocked = <String>[
    'file:///etc/passwd',
    'ftp://example.org/x',
    'data:text/plain,hallo',
    'javascript:alert(1)',
    'http://localhost:8080/',
    'http://LOCALHOST/',
    'http://localhost./',
    'http://api.localhost/',
    'http://drucker.local/',
    'http://nas.lan/',
    'http://router.home.arpa/',
    'http://dienst.internal/',
    'http://127.0.0.1/',
    'http://127.8.9.10/',
    'http://10.0.0.1/',
    'http://10.255.255.255/',
    'http://192.168.0.1/',
    'http://192.168.178.20:8123/',
    'http://172.16.0.1/',
    'http://172.31.255.255/',
    'http://169.254.169.254/latest/meta-data/',
    'http://100.64.0.1/',
    'http://100.127.255.254/',
    'http://0.0.0.0/',
    'http://224.0.0.1/',
    'http://255.255.255.255/',
    'http://[::1]/',
    'http://[::]/',
    'http://[fd00::1]/',
    'http://[fc00::1]/',
    'http://[fe80::1]/',
    'http://[ff02::1]/',
    'http://[::ffff:127.0.0.1]/',
    'http://[::ffff:192.168.1.1]/',
    'http://[64:ff9b::a00:1]/',
    'http://2130706433/',
    'http://0x7f000001/',
    'http://0x7f.0.0.1/',
    'http://127.1/',
    'http://017700000001/',
    'http://user:pass@example.org/',
    'http://rebind.example.org/',
    'http://mixed.example.org/',
  ];
  for (final url in blocked) {
    test('blockiert: $url', () async {
      await expectLater(
        check(url),
        throwsA(
          isA<PortException>()
              .having((e) => e.kind, 'kind', PortErrorKind.rejected)
              .having(
                (e) => e.message,
                'message',
                startsWith('Adresse nicht erlaubt'),
              ),
        ),
      );
    });
  }

  final allowed = <String>[
    'https://example.org/artikel',
    'http://example.org:8080/',
    'https://v6.example.org/',
    'http://93.184.216.34/',
    'http://172.32.0.1/',
    'http://172.15.255.255/',
    'http://100.128.0.1/',
    'http://192.169.0.1/',
    'http://[2606:2800:220:1::1]/',
  ];
  for (final url in allowed) {
    test('erlaubt: $url', () async {
      await check(url);
    });
  }

  group('Allowlist', () {
    test('erlaubt private Ziele ausdrücklich', () async {
      await check('http://192.168.1.10:8123/', allowed: {'192.168.1.10'});
      await check('http://homeserver.local/', allowed: {'homeserver.local'});
      await check(
        'http://rebind.example.org/',
        allowed: {'rebind.example.org'},
      );
    });

    test('gilt nur für den genannten Host', () async {
      await expectLater(
        check('http://192.168.1.11/', allowed: {'192.168.1.10'}),
        throwsA(isA<PortException>()),
      );
    });

    test('ersetzt nicht die Schema-Prüfung', () async {
      await expectLater(
        check('file://homeserver.local/x', allowed: {'homeserver.local'}),
        throwsA(isA<PortException>()),
      );
    });
  });

  test('unbekannter Host: unavailable', () async {
    for (final url in [
      'https://gibtsnicht.example/',
      'https://leer.example.org/',
    ]) {
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

  test('isPrivateAddress: IPv4-kompatible IPv6 und öffentliche Adressen', () {
    expect(isPrivateAddress(InternetAddress('::10.0.0.1')), isTrue);
    expect(isPrivateAddress(InternetAddress('::8.8.8.8')), isFalse);
    expect(isPrivateAddress(InternetAddress('8.8.8.8')), isFalse);
    expect(isPrivateAddress(InternetAddress('fec0::1')), isTrue);
    expect(isPrivateAddress(InternetAddress('2001:4860:4860::8888')), isFalse);
    expect(isPrivateAddress(InternetAddress('198.18.0.1')), isTrue);
    expect(isPrivateAddress(InternetAddress('192.0.0.8')), isTrue);
  });

  group('SIIT, 6to4 und Discard', () {
    const blocked = [
      '::ffff:0:c0a8:101',
      '::ffff:0:7f00:1',
      '2002:c0a8:101::1',
      '2002:7f00:1::1',
      '2002:a9fe:a9fe::1',
      '100::1',
    ];
    const allowedLiterals = ['2002:5db8:d822::1', '::ffff:0:5db8:d822'];
    for (final a in blocked) {
      test('lehnt $a ab (Literal und DNS)', () async {
        await expectLater(check('http://[$a]/'), throwsA(isA<PortException>()));
        await expectLater(
          checkFetchTarget(
            Uri.parse('https://dns.example.org/'),
            allowedHosts: const {},
            resolve: (_) async => [InternetAddress(a)],
          ),
          throwsA(isA<PortException>()),
        );
      });
    }
    for (final a in allowedLiterals) {
      test('erlaubt $a (Literal und DNS)', () async {
        await check('http://[$a]/');
        await checkFetchTarget(
          Uri.parse('https://dns.example.org/'),
          allowedHosts: const {},
          resolve: (_) async => [InternetAddress(a)],
        );
      });
    }
  });
}
