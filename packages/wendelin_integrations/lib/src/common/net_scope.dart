// Gemeinsamer Netzziel-Kern (WP36): die einzige Stelle, die Adressbereiche
// klassifiziert. Die Policies (`web/fetch_guard.dart`,
// `http_tools/http_target.dart`) entscheiden nur noch, welche Bereiche sie
// erlauben und welche Meldung kommt. Siehe ADR 0011.

import 'dart:io';

/// Resolves a host name to its addresses (default: [InternetAddress.lookup]).
typedef HostResolver = Future<List<InternetAddress>> Function(String host);

/// Address range of an IP address, one value per range the policies tell
/// apart. IPv4 embedded in IPv6 is classified by its IPv4 part (see
/// [Ipv4Embedding]).
enum NetScope {
  /// Routable on the internet.
  public,

  /// Loopback: `127.0.0.0/8`, `::1`.
  loopback,

  /// RFC 1918: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`.
  privateNetwork,

  /// Carrier-grade NAT `100.64.0.0/10` (also Tailscale).
  carrierNat,

  /// IPv6 unique local `fc00::/7` (also Tailscale `fd7a:…`).
  uniqueLocal,

  /// Deprecated IPv6 site-local `fec0::/10`.
  siteLocal,

  /// Link-local: `169.254.0.0/16`, `fe80::/10`.
  linkLocal,

  /// "This network" `0.0.0.0/8` and the unspecified IPv6 address `::`.
  unspecified,

  /// IETF protocol assignments `192.0.0.0/24`.
  ietfProtocol,

  /// Benchmarking `198.18.0.0/15`.
  benchmark,

  /// Multicast: `224.0.0.0/4`, `ff00::/8`.
  multicast,

  /// Reserved `240.0.0.0/4`, including broadcast `255.255.255.255`.
  reserved,

  /// IPv6 discard prefix `100::/64`.
  discard,

  /// Neither a 4-byte IPv4 nor a 16-byte IPv6 address.
  invalid,
}

/// How an IPv4 address is carried inside an IPv6 address.
enum Ipv4Embedding {
  /// Not embedded (plain IPv4 or native IPv6).
  none,

  /// IPv4-mapped `::ffff:a.b.c.d`.
  mapped,

  /// IPv4-compatible `::a.b.c.d` (except `::` and `::1`).
  compatible,

  /// SIIT `::ffff:0:a.b.c.d`.
  siit,

  /// NAT64 `64:ff9b::/32` (covers `64:ff9b::/96` and `64:ff9b:1::/48`);
  /// the IPv4 part is the last four bytes.
  nat64,

  /// 6to4 `2002::/16`; the IPv4 part follows the prefix.
  sixToFour,
}

/// Range and embedding of an address, see [classifyNet].
typedef NetClass = ({NetScope scope, Ipv4Embedding embedding});

/// The [NetScope] of [address] and how an IPv4 part is embedded in it.
NetClass classifyNet(InternetAddress address) {
  final b = address.rawAddress;
  if (address.type == InternetAddressType.IPv4 && b.length == 4) {
    return _v4(b, Ipv4Embedding.none);
  }
  if (address.type != InternetAddressType.IPv6 || b.length != 16) {
    return _native(NetScope.invalid);
  }
  final zeroPrefix = _zero(b, 0, 10);
  if (zeroPrefix && b[10] == 0 && b[11] == 0) {
    if (_zero(b, 12, 15)) {
      if (b[15] == 0) return _native(NetScope.unspecified); // ::
      if (b[15] == 1) return _native(NetScope.loopback); // ::1
    }
    return _v4(b.sublist(12), Ipv4Embedding.compatible);
  }
  if (zeroPrefix && b[10] == 0xff && b[11] == 0xff) {
    return _v4(b.sublist(12), Ipv4Embedding.mapped);
  }
  if (_zero(b, 0, 8) &&
      b[8] == 0xff &&
      b[9] == 0xff &&
      b[10] == 0 &&
      b[11] == 0) {
    return _v4(b.sublist(12), Ipv4Embedding.siit);
  }
  if (b[0] == 0 && b[1] == 0x64 && b[2] == 0xff && b[3] == 0x9b) {
    return _v4(b.sublist(12), Ipv4Embedding.nat64);
  }
  if (b[0] == 0x01 && _zero(b, 1, 8)) return _native(NetScope.discard);
  if (b[0] == 0x20 && b[1] == 0x02) {
    return _v4(b.sublist(2, 6), Ipv4Embedding.sixToFour);
  }
  if ((b[0] & 0xfe) == 0xfc) return _native(NetScope.uniqueLocal);
  if (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) return _native(NetScope.linkLocal);
  if (b[0] == 0xfe && (b[1] & 0xc0) == 0xc0) return _native(NetScope.siteLocal);
  if (b[0] == 0xff) return _native(NetScope.multicast);
  return _native(NetScope.public);
}

NetClass _native(NetScope scope) =>
    (scope: scope, embedding: Ipv4Embedding.none);

bool _zero(List<int> b, int from, int to) {
  for (var i = from; i < to; i++) {
    if (b[i] != 0) return false;
  }
  return true;
}

NetClass _v4(List<int> b, Ipv4Embedding embedding) =>
    (scope: _scopeV4(b), embedding: embedding);

NetScope _scopeV4(List<int> b) {
  final a0 = b[0];
  final a1 = b[1];
  return switch (a0) {
    0 => NetScope.unspecified,
    10 => NetScope.privateNetwork,
    127 => NetScope.loopback,
    100 when a1 >= 64 && a1 <= 127 => NetScope.carrierNat,
    169 when a1 == 254 => NetScope.linkLocal,
    172 when a1 >= 16 && a1 <= 31 => NetScope.privateNetwork,
    192 when a1 == 168 => NetScope.privateNetwork,
    192 when a1 == 0 && b[2] == 0 => NetScope.ietfProtocol,
    198 when a1 == 18 || a1 == 19 => NetScope.benchmark,
    >= 224 && < 240 => NetScope.multicast,
    >= 240 => NetScope.reserved,
    _ => NetScope.public,
  };
}

/// Lower-case [host] without a trailing dot.
String normalizeHostName(String host) {
  final h = host.toLowerCase();
  return h.endsWith('.') ? h.substring(0, h.length - 1) : h;
}

/// Whether the normalized [host] is `localhost` or a `*.localhost` name.
bool isLocalhostName(String host) =>
    host == 'localhost' || host.endsWith('.localhost');

final _numericHost = RegExp(r'^(0x[0-9a-f]*|[0-9]+)(\.(0x[0-9a-f]*|[0-9]+))*$');

/// Whether the normalized [host] is a numeric spelling such as `2130706433`,
/// `0x7f.1` or `127.1` that resolvers read differently (check after literal
/// parsing, a canonical dotted quad matches too).
bool isNumericHostSpelling(String host) => _numericHost.hasMatch(host);
