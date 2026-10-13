// Policy von web__fetch: nur öffentliche Ziele. Adressbereiche
// klassifiziert `common/net_scope.dart`.

import 'dart:io';

import '../common/net_scope.dart';
import '../common/port_exception.dart';

export '../common/net_scope.dart' show HostResolver;

const _privateSuffixes = ['.local', '.internal', '.lan', '.home.arpa'];

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
  final trimmed = normalizeHostName(host);
  if (isLocalhostName(trimmed) || _privateSuffixes.any(trimmed.endsWith)) {
    throw _blocked('lokales Ziel „$host“');
  }
  final literal = InternetAddress.tryParse(trimmed);
  if (literal != null) {
    if (isPrivateAddress(literal)) throw _blocked('privates Netz „$host“');
    return;
  }
  // Numerische Schreibweisen wie 2130706433 oder 0x7f.1 meinen IP-Adressen,
  // die der Resolver unterschiedlich deuten würde.
  if (isNumericHostSpelling(trimmed)) {
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
///
/// Unlike `checkHttpTarget`, this policy does not look into SIIT and 6to4
/// addresses and lets the discard prefix `100::/64` pass (behaviour before
/// WP36, kept unchanged).
bool isPrivateAddress(InternetAddress address) {
  final (:scope, :embedding) = classifyNet(address);
  return switch (embedding) {
    Ipv4Embedding.siit || Ipv4Embedding.sixToFour => false,
    _ => scope != NetScope.public && scope != NetScope.discard,
  };
}
