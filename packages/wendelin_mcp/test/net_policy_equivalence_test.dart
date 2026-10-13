import 'package:test/test.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

import 'legacy_net_policy.dart';

// Vergleichstest (WP36 b): die Host-Prüfung auf dem gemeinsamen Netzziel-Kern
// entscheidet für jede Adresse wie die eingefrorene Altfassung.
const _hosts = <String>[
  'localhost',
  'LOCALHOST.',
  'foo.localhost',
  'notlocalhost',
  'example.com',
  'a.ts.net',
  'x.local',
  'x.home.arpa',
  'home.arpa',
  'evil.ts.net.com',
  '10.0.0.1.',
  'FC00::1',
  '[fe80::1]',
  '127.0.0.1',
  '127.255.255.255',
  '126.255.255.255',
  '128.0.0.0',
  '10.0.0.0',
  '10.255.255.255',
  '9.255.255.255',
  '11.0.0.0',
  '10.0.2.2',
  '172.15.255.255',
  '172.16.0.0',
  '172.31.255.255',
  '172.32.0.0',
  '192.168.0.0',
  '192.168.255.255',
  '192.167.255.255',
  '192.169.0.0',
  '100.63.255.255',
  '100.64.0.0',
  '100.127.255.255',
  '100.128.0.0',
  '169.254.1.1',
  '0.0.0.0',
  '224.0.0.1',
  '240.0.0.1',
  '255.255.255.255',
  '8.8.8.8',
  '192.0.0.1',
  '198.18.0.1',
  '::1',
  '[::1]',
  '::',
  'fc00::1',
  'fd7a:115c::1',
  'fdff::1',
  'fbff::1',
  'fe00::1',
  'fe80::1',
  'febf::1',
  'fec0::1',
  'ff02::1',
  '2001:db8::1',
  '2606:4700::1',
  '2002:7f00:1::',
  '64:ff9b::7f00:1',
  '::ffff:127.0.0.1',
  '::ffff:10.0.0.1',
  '::ffff:192.168.1.1',
  '::ffff:8.8.8.8',
  '::ffff:100.64.0.1',
  '::7f00:1',
  '::a00:1',
  '::ffff:0:a00:1',
  '100::1',
];

void main() {
  test('Liste hat mindestens 40 Hosts', () {
    expect(_hosts.length, greaterThanOrEqualTo(40));
  });

  for (final h in _hosts) {
    test('Host $h', () {
      expect(isLoopbackHost(h), legacyIsLoopbackHost(h), reason: 'loopback');
      expect(isHomeNetworkHost(h), legacyIsHomeNetworkHost(h), reason: 'home');
    });
  }
}
