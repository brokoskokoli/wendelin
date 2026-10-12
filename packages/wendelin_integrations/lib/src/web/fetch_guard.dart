import 'dart:io';

import '../common/port_exception.dart';

/// Resolves a host name to its addresses (default: [InternetAddress.lookup]).
typedef HostResolver = Future<List<InternetAddress>> Function(String host);

const _privateSuffixes = [
  '.localhost',
  '.local',
  '.internal',
  '.lan',
  '.home.arpa',
];

final _numericHost = RegExp(r'^(0x[0-9a-f]*|[0-9]+)(\.(0x[0-9a-f]*|[0-9]+))*$');

PortException _blocked(String why) =>
    PortException(PortErrorKind.rejected, 'Adresse nicht erlaubt: $why');

/// Checks that [url] may be fetched: only `http`/`https`, no credentials
/// in the URL, no local or private targets unless the host is in
/// [allowedHosts] (lower-case host names or IP literals).
///
/// Host names are resolved with [resolve] and rejected if any address is
/// private (protects against names pointing into the home network). Throws
/// `PortException(rejected)`.
Future<void> checkFetchTarget(
  Uri url, {
  required Set<String> allowedHosts,
  required HostResolver resolve,
}) async {
  if (!url.isScheme('http') && !url.isScheme('https')) {
    throw _blocked('nur http- und https-Adressen sind erlaubt');
  }
  if (url.userInfo.isNotEmpty) {
    throw _blocked('Zugangsdaten in der Adresse');
  }
  final host = url.host.toLowerCase();
  if (host.isEmpty) throw _blocked('kein Host');
  if (allowedHosts.contains(host)) return;
  final trimmed = host.endsWith('.')
      ? host.substring(0, host.length - 1)
      : host;
  if (trimmed == 'localhost' || _privateSuffixes.any(trimmed.endsWith)) {
    throw _blocked('lokales Ziel „$host“');
  }
  final literal = InternetAddress.tryParse(trimmed);
  if (literal != null) {
    if (isPrivateAddress(literal)) throw _blocked('privates Netz „$host“');
    return;
  }
  // Numerische Schreibweisen wie 2130706433 oder 0x7f.1 meinen IP-Adressen,
  // die der Resolver unterschiedlich deuten würde.
  if (_numericHost.hasMatch(trimmed)) {
    throw _blocked('ungewöhnliche IP-Schreibweise „$host“');
  }
  final List<InternetAddress> addresses;
  try {
    addresses = await resolve(trimmed);
  } on SocketException {
    throw PortException(
      PortErrorKind.unavailable,
      'Host „$host“ nicht gefunden',
    );
  }
  if (addresses.isEmpty) {
    throw PortException(
      PortErrorKind.unavailable,
      'Host „$host“ nicht gefunden',
    );
  }
  for (final a in addresses) {
    if (isPrivateAddress(a)) {
      throw _blocked('„$host“ zeigt in ein privates Netz');
    }
  }
}

/// Whether [address] is loopback, private, link-local, CGNAT, multicast,
/// reserved or unspecified (IPv4 and IPv6, including IPv4-mapped).
bool isPrivateAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) return _privateV4(b);
  if (address.type != InternetAddressType.IPv6 || b.length != 16) return true;
  final allZeroPrefix = b.sublist(0, 10).every((x) => x == 0);
  // ::ffff:a.b.c.d (IPv4-mapped) und ::a.b.c.d (IPv4-kompatibel).
  if (allZeroPrefix &&
      ((b[10] == 0xff && b[11] == 0xff) || (b[10] == 0 && b[11] == 0))) {
    if (b[10] == 0 && b.sublist(12).every((x) => x == 0)) return true; // ::
    if (b[10] == 0 && b.sublist(12, 15).every((x) => x == 0) && b[15] == 1) {
      return true; // ::1
    }
    return _privateV4(b.sublist(12));
  }
  // 64:ff9b::/96 (NAT64) trägt eine IPv4-Adresse.
  if (b[0] == 0 && b[1] == 0x64 && b[2] == 0xff && b[3] == 0x9b) {
    return _privateV4(b.sublist(12));
  }
  if ((b[0] & 0xfe) == 0xfc) return true; // fc00::/7 ULA
  if (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) return true; // fe80::/10
  if (b[0] == 0xfe && (b[1] & 0xc0) == 0xc0) return true; // fec0::/10
  if (b[0] == 0xff) return true; // Multicast
  return false;
}

bool _privateV4(List<int> b) {
  final a0 = b[0];
  final a1 = b[1];
  return a0 == 0 || // 0.0.0.0/8
      a0 == 10 || // 10.0.0.0/8
      a0 == 127 || // Loopback
      (a0 == 100 && a1 >= 64 && a1 <= 127) || // 100.64.0.0/10 CGNAT
      (a0 == 169 && a1 == 254) || // Link-local
      (a0 == 172 && a1 >= 16 && a1 <= 31) || // 172.16.0.0/12
      (a0 == 192 && a1 == 168) || // 192.168.0.0/16
      (a0 == 192 && a1 == 0 && b[2] == 0) || // 192.0.0.0/24
      (a0 == 198 && (a1 == 18 || a1 == 19)) || // Benchmark
      a0 >= 224; // Multicast, reserviert, Broadcast
}
