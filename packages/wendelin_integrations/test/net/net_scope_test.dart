import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

void main() {
  group('classifyNet: IPv4-Grenzen je Bereich (erste, letzte, ±1)', () {
    const table = <String, NetScope>{
      '0.0.0.0': NetScope.unspecified,
      '0.255.255.255': NetScope.unspecified,
      '1.0.0.0': NetScope.public,
      '9.255.255.255': NetScope.public,
      '10.0.0.0': NetScope.privateNetwork,
      '10.255.255.255': NetScope.privateNetwork,
      '11.0.0.0': NetScope.public,
      '100.63.255.255': NetScope.public,
      '100.64.0.0': NetScope.carrierNat,
      '100.127.255.255': NetScope.carrierNat,
      '100.128.0.0': NetScope.public,
      '126.255.255.255': NetScope.public,
      '127.0.0.0': NetScope.loopback,
      '127.255.255.255': NetScope.loopback,
      '128.0.0.0': NetScope.public,
      '169.253.255.255': NetScope.public,
      '169.254.0.0': NetScope.linkLocal,
      '169.254.255.255': NetScope.linkLocal,
      '169.255.0.0': NetScope.public,
      '172.15.255.255': NetScope.public,
      '172.16.0.0': NetScope.privateNetwork,
      '172.31.255.255': NetScope.privateNetwork,
      '172.32.0.0': NetScope.public,
      '191.255.255.255': NetScope.public,
      '192.0.0.0': NetScope.ietfProtocol,
      '192.0.0.255': NetScope.ietfProtocol,
      '192.0.1.0': NetScope.public,
      '192.167.255.255': NetScope.public,
      '192.168.0.0': NetScope.privateNetwork,
      '192.168.255.255': NetScope.privateNetwork,
      '192.169.0.0': NetScope.public,
      '198.17.255.255': NetScope.public,
      '198.18.0.0': NetScope.benchmark,
      '198.19.255.255': NetScope.benchmark,
      '198.20.0.0': NetScope.public,
      '223.255.255.255': NetScope.public,
      '224.0.0.0': NetScope.multicast,
      '239.255.255.255': NetScope.multicast,
      '240.0.0.0': NetScope.reserved,
      '255.255.255.255': NetScope.reserved,
    };
    for (final MapEntry(key: address, value: scope) in table.entries) {
      test('$address → ${scope.name}', () {
        expect(classifyNet(InternetAddress(address)), (
          scope: scope,
          embedding: Ipv4Embedding.none,
        ));
      });
    }
  });

  group('classifyNet: IPv6-Grenzen je Bereich', () {
    const table = <String, NetScope>{
      '::': NetScope.unspecified,
      '::1': NetScope.loopback,
      '0:0:0:0:0:1::': NetScope.public,
      'ff::1': NetScope.public,
      '100::': NetScope.discard,
      '100::ffff:ffff:ffff:ffff': NetScope.discard,
      '100:0:0:1::': NetScope.public,
      '2002::': NetScope.unspecified, // 6to4 von 0.0.0.0
      '2606:2800:220:1::1': NetScope.public,
      '64:ff9a:ffff::1': NetScope.public,
      '64:ff9c::1': NetScope.public,
      'fbff:ffff:ffff:ffff:ffff:ffff:ffff:ffff': NetScope.public,
      'fc00::': NetScope.uniqueLocal,
      'fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff': NetScope.uniqueLocal,
      'fe00::': NetScope.public,
      'fe7f:ffff:ffff:ffff:ffff:ffff:ffff:ffff': NetScope.public,
      'fe80::': NetScope.linkLocal,
      'febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff': NetScope.linkLocal,
      'fec0::': NetScope.siteLocal,
      'feff:ffff:ffff:ffff:ffff:ffff:ffff:ffff': NetScope.siteLocal,
      'ff00::': NetScope.multicast,
      'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff': NetScope.multicast,
    };
    for (final MapEntry(key: address, value: scope) in table.entries) {
      test('$address → ${scope.name}', () {
        expect(classifyNet(InternetAddress(address)).scope, scope);
      });
    }
  });

  group('classifyNet: IPv4 in IPv6 nach dem IPv4-Teil', () {
    const table = <String, (NetScope, Ipv4Embedding)>{
      '::ffff:10.0.0.1': (NetScope.privateNetwork, Ipv4Embedding.mapped),
      '::ffff:127.0.0.1': (NetScope.loopback, Ipv4Embedding.mapped),
      '::ffff:8.8.8.8': (NetScope.public, Ipv4Embedding.mapped),
      '::ffff:0.0.0.0': (NetScope.unspecified, Ipv4Embedding.mapped),
      '::0.0.0.2': (NetScope.unspecified, Ipv4Embedding.compatible),
      '::10.0.0.1': (NetScope.privateNetwork, Ipv4Embedding.compatible),
      '::8.8.8.8': (NetScope.public, Ipv4Embedding.compatible),
      '::ffff:0:192.168.1.1': (NetScope.privateNetwork, Ipv4Embedding.siit),
      '::ffff:0:100.64.0.0': (NetScope.carrierNat, Ipv4Embedding.siit),
      '64:ff9b::169.254.169.254': (NetScope.linkLocal, Ipv4Embedding.nat64),
      '64:ff9b:1::100.127.255.255': (NetScope.carrierNat, Ipv4Embedding.nat64),
      '64:ff9b::100.128.0.0': (NetScope.public, Ipv4Embedding.nat64),
      '2002:a00:1::1': (NetScope.privateNetwork, Ipv4Embedding.sixToFour),
      '2002:7f00:1::': (NetScope.loopback, Ipv4Embedding.sixToFour),
      '2002:808:808::1': (NetScope.public, Ipv4Embedding.sixToFour),
    };
    for (final MapEntry(key: address, value: (scope, embedding))
        in table.entries) {
      test('$address → ${scope.name} (${embedding.name})', () {
        expect(classifyNet(InternetAddress(address)), (
          scope: scope,
          embedding: embedding,
        ));
      });
    }
  });

  test('classifyNet: ungültige Rohadresse ist invalid', () {
    final odd = InternetAddress.fromRawAddress(
      Uint8List.fromList([1, 2, 3, 4]),
      type: InternetAddressType.unix,
    );
    expect(classifyNet(odd).scope, NetScope.invalid);
  });

  test('Policies: Sicht der Web-Abrufe und HTTP-Tools', () {
    // web__fetch: alles außer öffentlich ist privat; SIIT, 6to4 und
    // 100::/64 bleiben wie vor WP36 öffentlich.
    expect(isPrivateAddress(InternetAddress('100.64.0.0')), isTrue);
    expect(isPrivateAddress(InternetAddress('100.63.255.255')), isFalse);
    expect(isPrivateAddress(InternetAddress('fe80::1')), isTrue);
    expect(isPrivateAddress(InternetAddress('::ffff:0:10.0.0.1')), isFalse);
    expect(isPrivateAddress(InternetAddress('2002:a00:1::1')), isFalse);
    expect(isPrivateAddress(InternetAddress('100::1')), isFalse);
    // HTTP-Tools: Grobklassen.
    expect(
      classifyAddress(InternetAddress('100.127.255.255')),
      AddressScope.private,
    );
    expect(classifyAddress(InternetAddress('fec0::1')), AddressScope.private);
    expect(classifyAddress(InternetAddress('100::1')), AddressScope.blocked);
    expect(
      classifyAddress(InternetAddress('::ffff:0:10.0.0.1')),
      AddressScope.private,
    );
  });

  group('Host-Namen', () {
    test('normalizeHostName', () {
      expect(normalizeHostName('Example.ORG.'), 'example.org');
      expect(normalizeHostName('a.b'), 'a.b');
    });
    test('isLocalhostName', () {
      expect(isLocalhostName('localhost'), isTrue);
      expect(isLocalhostName('app.localhost'), isTrue);
      expect(isLocalhostName('xlocalhost'), isFalse);
      expect(isLocalhostName('localhost.example.org'), isFalse);
    });
    test('isNumericHostSpelling', () {
      for (final h in ['2130706433', '0x7f.1', '127.1', '010.0.0.1', '0x']) {
        expect(isNumericHostSpelling(h), isTrue, reason: h);
      }
      for (final h in ['example.org', '1.2.3.a', 'x1']) {
        expect(isNumericHostSpelling(h), isFalse, reason: h);
      }
    });
  });
}
