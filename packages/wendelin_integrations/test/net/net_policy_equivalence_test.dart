// Vergleichstest WP36 a: Die Netzziel-Policies auf dem gemeinsamen Kern
// (`common/net_scope.dart`) müssen für jede Adresse dasselbe Ergebnis
// liefern wie die eingefrorene Implementierung vor dem Umbau
// (`legacy_net_rules.dart`). Geschrieben vor dem Umbau, danach unverändert.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'legacy_net_rules.dart';

/// IPv4-Grenzfälle: erste/letzte Adresse jedes Bereichs und ±1 außerhalb.
const _v4Edges = [
  '0.0.0.0', '0.0.0.1', '0.255.255.255', '1.0.0.0', //
  '9.255.255.255', '10.0.0.0', '10.0.2.2', '10.255.255.255', '11.0.0.0',
  '100.63.255.255', '100.64.0.0', '100.101.102.103', '100.127.255.255',
  '100.128.0.0',
  '126.255.255.255', '127.0.0.0', '127.0.0.1', '127.255.255.255',
  '128.0.0.0',
  '169.253.255.255', '169.254.0.0', '169.254.169.254', '169.254.255.255',
  '169.255.0.0',
  '172.15.255.255', '172.16.0.0', '172.31.255.255', '172.32.0.0',
  '191.255.255.255', '192.0.0.0', '192.0.0.255', '192.0.1.0',
  '192.167.255.255', '192.168.0.0', '192.168.178.20', '192.168.255.255',
  '192.169.0.0',
  '198.17.255.255', '198.18.0.0', '198.19.255.255', '198.20.0.0',
  '223.255.255.255', '224.0.0.0', '239.255.255.255', '240.0.0.0',
  '255.255.255.254', '255.255.255.255',
  '1.1.1.1', '8.8.8.8', '93.184.216.34', '203.0.113.7',
];

/// IPv6-Grenzfälle (ohne eingebettetes IPv4).
const _v6Edges = [
  '::', '::1', '::2', '::fffe:ffff:ffff', '::1:0:0:0', '::1:ffff:a00:1', //
  '1::', '100::', '100::ffff:ffff:ffff:ffff', '100:0:0:1::', '0:ffff::1',
  'ff::1', '200::', '2001::1', '2001:db8::1', '2001:ffff::1', '2002::',
  '2002:ffff:ffff::', '2003::', '2606:2800:220:1::1', '2a00:1450::1',
  '63:ffff::1', '64:ff9a:ffff::1', '64:ff9b::', '64:ff9b:1::',
  '64:ff9b:ffff::1', '64:ff9c::1', '65::1',
  'fbff:ffff:ffff:ffff:ffff:ffff:ffff:ffff', 'fc00::', 'fd7a:115c:a1e0::1',
  'fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff', 'fe00::', 'fe7f:ffff::1',
  'fe80::', 'fe80::1', 'febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff', 'fec0::',
  'feff:ffff:ffff:ffff:ffff:ffff:ffff:ffff', 'ff00::', 'ff02::1',
  'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff',
];

/// IPv4 [v4] in allen IPv6-Einbettungen (mapped, kompatibel, SIIT, NAT64,
/// lokales NAT64, NAT64 außerhalb /96, 6to4).
List<String> _embeddings(String v4) {
  final p = v4.split('.').map(int.parse).toList();
  String hex(int a, int b) => ((a << 8) | b).toRadixString(16);
  final hi = hex(p[0], p[1]);
  final lo = hex(p[2], p[3]);
  return [
    '::ffff:$v4',
    '::$v4',
    '::ffff:0:$v4',
    '64:ff9b::$v4',
    '64:ff9b:1::$v4',
    '64:ff9b:1:2:3:4:$hi:$lo',
    '2002:$hi:$lo::1',
    '2002:$hi:$lo:ffff::$v4',
  ];
}

/// Präfixe, um die die Zufallsadressen streuen.
const _v6Prefixes = [
  [0, 0], [0, 0x64], [0x01, 0], [0x20, 0x01], [0x20, 0x02], [0x26, 0x06], //
  [0xfc, 0], [0xfd, 0x7a], [0xfe, 0x80], [0xfe, 0xbf], [0xfe, 0xc0],
  [0xff, 0x02],
];

List<InternetAddress> _addresses() {
  final out = <InternetAddress>[
    for (final a in _v4Edges) InternetAddress(a),
    for (final a in _v4Edges) ..._embeddings(a).map(InternetAddress.new),
    for (final a in _v6Edges) InternetAddress(a),
  ];
  final random = Random(36);
  int byte() => random.nextInt(256);
  for (var i = 0; i < 1500; i++) {
    // Erstes Oktett gleichverteilt, Rest zufällig.
    out.add(
      InternetAddress.fromRawAddress(
        Uint8List.fromList([i % 256, byte(), byte(), byte()]),
      ),
    );
  }
  for (var i = 0; i < 1500; i++) {
    final prefix = _v6Prefixes[i % _v6Prefixes.length];
    final b = [for (var j = 0; j < 16; j++) byte()];
    b[0] = prefix[0];
    b[1] = prefix[1];
    // Für Einbettungsformen häufig die Nullfolgen treffen.
    if (i % 3 == 0) {
      for (var j = 2; j < 10; j++) {
        b[j] = 0;
      }
      if (i % 2 == 0) b[10] = b[11] = 0xff;
    }
    if (prefix[1] == 0x64 && i % 2 == 0) {
      b[2] = 0xff;
      b[3] = 0x9b;
    }
    out.add(InternetAddress.fromRawAddress(Uint8List.fromList(b)));
  }
  return out;
}

String _uriHost(InternetAddress a) =>
    a.type == InternetAddressType.IPv6 ? '[${a.address}]' : a.address;

/// Ergebnis einer Prüfung als vergleichbarer Text.
Future<String> _outcome(Future<Object?> Function() run) async {
  try {
    final r = await run();
    return switch (r) {
      HttpTarget(:final origin, :final addresses, :final homeNetwork) =>
        'ok $origin $addresses $homeNetwork',
      (
        origin: final Uri origin,
        addresses: final List<InternetAddress> addresses,
        homeNetwork: final bool homeNetwork,
      ) =>
        'ok $origin $addresses $homeNetwork',
      _ => 'ok',
    };
  } on PortException catch (e) {
    return '${e.kind.name}: ${e.message}';
  } on Object catch (e) {
    return 'error ${e.runtimeType}';
  }
}

/// Gewollte Abweichung seit dem Sicherheitsfix: web__fetch bewertet SIIT,
/// 6to4 und `100::/64` jetzt wie die HTTP-Tools (vorher öffentlich).
/// Für diese Adressen gilt nicht mehr der eingefrorene Stand, sondern
/// `scope != public`.
bool _intendedWebDeviation(InternetAddress a) {
  final c = classifyNet(a);
  return c.embedding == Ipv4Embedding.siit ||
      c.embedding == Ipv4Embedding.sixToFour ||
      c.scope == NetScope.discard;
}

void main() {
  final addresses = _addresses();
  const name = 'ziel.example.org';
  const homeName = 'nas.home.arpa';
  const public = '93.184.216.34';

  test('Adressliste ist groß genug und enthält beide Familien', () {
    expect(addresses.length, greaterThan(3000));
    expect(
      addresses.where((a) => a.type == InternetAddressType.IPv6).length,
      greaterThan(1500),
    );
  });

  test('isPrivateAddress (web__fetch) unverändert', () {
    for (final a in addresses) {
      if (_intendedWebDeviation(a)) {
        expect(
          isPrivateAddress(a),
          classifyNet(a).scope != NetScope.public,
          reason: '$a',
        );
        continue;
      }
      expect(isPrivateAddress(a), legacyIsPrivateAddress(a), reason: '$a');
    }
  });

  test('classifyAddress (HTTP-Tools) unverändert', () {
    for (final a in addresses) {
      expect(
        classifyAddress(a).name,
        legacyClassifyAddress(a).name,
        reason: '$a',
      );
    }
  });

  test('isHomeNetworkHost (HTTP-Tools) unverändert', () {
    for (final a in addresses) {
      for (final h in [
        a.address,
        a.address.toUpperCase(),
        '${a.address}.',
        if (a.type == InternetAddressType.IPv6) '[${a.address}]',
      ]) {
        expect(isHomeNetworkHost(h), legacyIsHomeNetworkHost(h), reason: h);
      }
    }
  });

  test('checkFetchTarget (web__fetch) unverändert', () async {
    for (final a in addresses) {
      if (_intendedWebDeviation(a)) continue;
      final lit = _uriHost(a);
      Future<List<InternetAddress>> dns(String host) async => switch (host) {
        name => [a],
        'gemischt.example.org' => [InternetAddress(public), a],
        _ => throw const SocketException('NXDOMAIN'),
      };
      for (final url in [
        'https://$lit/x',
        'http://$lit:8080/',
        'https://$name/',
        'http://gemischt.example.org/',
      ]) {
        for (final allowed in [
          <String>{},
          {a.address.toLowerCase(), name},
        ]) {
          final uri = Uri.parse(url);
          final now = await _outcome(
            () => checkFetchTarget(uri, allowedHosts: allowed, resolve: dns),
          );
          final before = await _outcome(
            () => legacyCheckFetchTarget(
              uri,
              allowedHosts: allowed,
              resolve: dns,
            ),
          );
          expect(now, before, reason: '$url $allowed');
        }
      }
    }
  });

  test('checkHttpTarget (HTTP-Tools) unverändert', () async {
    for (final a in addresses) {
      final lit = _uriHost(a);
      Future<List<InternetAddress>> dns(String host) async => switch (host) {
        name || homeName => [a],
        'gemischt.example.org' => [InternetAddress(public), a],
        _ => throw const SocketException('NXDOMAIN'),
      };
      for (final host in [lit, name, homeName, 'gemischt.example.org']) {
        for (final scheme in ['http', 'https']) {
          for (final home in [false, true]) {
            for (final loopback in [false, true]) {
              final uri = Uri.parse('$scheme://$host:8443/p');
              final now = await _outcome(
                () => checkHttpTarget(
                  uri,
                  homeNetwork: home,
                  resolve: dns,
                  allowLoopback: loopback,
                ),
              );
              final before = await _outcome(
                () => legacyCheckHttpTarget(
                  uri,
                  homeNetwork: home,
                  resolve: dns,
                  allowLoopback: loopback,
                ),
              );
              expect(now, before, reason: '$uri home=$home loop=$loopback');
            }
          }
        }
      }
    }
  });

  group('Host-Namen und Schreibweisen unverändert', () {
    const hosts = [
      'localhost', 'localhost.', 'LOCALHOST', 'app.localhost', 'xlocalhost', //
      'nas.local', 'nas.lan', 'nas.home', 'nas.home.arpa', 'nas.internal',
      'box.tail1234.ts.net', 'ts.net', 'local', 'example.local.org',
      'example.org', 'example.org.', 'EXAMPLE.ORG', '2130706433', '0x7f.1',
      '0x7f.0.0.1', '127.1', '010.0.0.1', '1.2.3', '1.2.3.4.5', '0', '0x',
      '[fe80::1%25eth0]', '[::1]', '[::ffff:7f00:1]', '[64:ff9b::a00:1]',
      '256.1.1.1', '01.2.3.4', 'a..b', '-',
    ];
    final answers = [
      for (final a in [
        '93.184.216.34',
        '192.168.1.2',
        '127.0.0.1',
        '169.254.1.1',
        '100.64.0.1',
        '0.0.0.0',
        '::ffff:0:a00:1',
        '2002:c0a8:101::1',
        '100::1',
        'fd7a:115c:a1e0::1',
      ])
        [InternetAddress(a)],
      <InternetAddress>[],
      null,
    ];
    for (final answer in answers) {
      test('Auflösung $answer', () async {
        Future<List<InternetAddress>> dns(String host) async =>
            answer ?? (throw const SocketException('NXDOMAIN'));
        for (final h in hosts) {
          expect(isHomeNetworkHost(h), legacyIsHomeNetworkHost(h), reason: h);
          for (final prefix in [
            'http://',
            'https://',
            'https://user:pw@',
            'ftp://',
          ]) {
            final Uri uri;
            try {
              uri = Uri.parse('$prefix$h/');
            } on FormatException {
              continue;
            }
            for (final allowed in [
              <String>{},
              {h.toLowerCase()},
            ]) {
              if (answer != null &&
                  answer.isNotEmpty &&
                  _intendedWebDeviation(answer.first)) {
                continue;
              }
              expect(
                await _outcome(
                  () => checkFetchTarget(
                    uri,
                    allowedHosts: allowed,
                    resolve: dns,
                  ),
                ),
                await _outcome(
                  () => legacyCheckFetchTarget(
                    uri,
                    allowedHosts: allowed,
                    resolve: dns,
                  ),
                ),
                reason: '$uri $allowed',
              );
            }
            for (final home in [false, true]) {
              for (final loopback in [false, true]) {
                expect(
                  await _outcome(
                    () => checkHttpTarget(
                      uri,
                      homeNetwork: home,
                      resolve: dns,
                      allowLoopback: loopback,
                    ),
                  ),
                  await _outcome(
                    () => legacyCheckHttpTarget(
                      uri,
                      homeNetwork: home,
                      resolve: dns,
                      allowLoopback: loopback,
                    ),
                  ),
                  reason: '$uri home=$home loop=$loopback',
                );
              }
            }
          }
        }
      });
    }
  });
}
