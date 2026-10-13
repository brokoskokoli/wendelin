// Zielprüfung der HTTP-Tools (SSRF, DNS-Rebinding), siehe ADR 0011. Nur die
// Policy; Adressbereiche klassifiziert `common/net_scope.dart`.

import 'dart:io';

import 'package:meta/meta.dart';

import '../common/net_scope.dart';
import '../common/port_exception.dart';

/// Network scope of an IP address as the HTTP-tool policy sees it.
enum AddressScope {
  /// Routable on the internet.
  public,

  /// Private network: [NetScope.privateNetwork], [NetScope.carrierNat]
  /// (Tailscale), [NetScope.uniqueLocal], [NetScope.siteLocal].
  private,

  /// Loopback ([NetScope.loopback]).
  loopback,

  /// Link-local ([NetScope.linkLocal]).
  linkLocal,

  /// Never a valid target: unspecified, multicast, broadcast, reserved,
  /// benchmark, IETF-protocol and discard ranges.
  blocked,
}

/// The [AddressScope] of [address]; IPv4 embedded in IPv6 (mapped,
/// compatible, SIIT, NAT64, 6to4) is classified by its IPv4 part
/// ([classifyNet]).
AddressScope classifyAddress(InternetAddress address) =>
    switch (classifyNet(address).scope) {
      NetScope.public => AddressScope.public,
      NetScope.loopback => AddressScope.loopback,
      NetScope.linkLocal => AddressScope.linkLocal,
      NetScope.privateNetwork ||
      NetScope.carrierNat ||
      NetScope.uniqueLocal ||
      NetScope.siteLocal => AddressScope.private,
      NetScope.unspecified ||
      NetScope.ietfProtocol ||
      NetScope.benchmark ||
      NetScope.multicast ||
      NetScope.reserved ||
      NetScope.discard ||
      NetScope.invalid => AddressScope.blocked,
    };

const _homeSuffixes = [
  '.local',
  '.lan',
  '.home',
  '.home.arpa',
  '.internal',
  '.ts.net',
];

final _dottedQuad = RegExp(
  r'^(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})$',
);

/// Whether [host] names a home-network target by itself: an IP literal of
/// [AddressScope.private] (LAN, Tailscale, ULA) or a name ending in
/// `.local`, `.lan`, `.home`, `.home.arpa`, `.internal` or `.ts.net`.
bool isHomeNetworkHost(String host) {
  final h = normalizeHostName(host);
  final literal = _literal(h);
  if (literal != null) return classifyAddress(literal) == AddressScope.private;
  return _homeSuffixes.any(h.endsWith);
}

InternetAddress? _literal(String host) {
  if (host.contains(':')) return InternetAddress.tryParse(host);
  return _dottedQuad.hasMatch(host) ? InternetAddress.tryParse(host) : null;
}

/// A checked target: the origin and the addresses the request must be
/// sent to (pinned, so a second DNS answer cannot redirect it).
@immutable
final class HttpTarget {
  /// Creates a checked target.
  HttpTarget({
    required this.origin,
    required List<InternetAddress> addresses,
    required this.homeNetwork,
  }) : addresses = List.unmodifiable(addresses);

  /// `scheme://host:port`.
  final Uri origin;

  /// Vetted addresses of the host, in resolver order.
  final List<InternetAddress> addresses;

  /// Whether the target counts as home network (marked or by name/IP).
  final bool homeNetwork;

  /// Whether [url] has the same scheme, host and port as [origin].
  bool sameOrigin(Uri url) =>
      url.scheme == origin.scheme &&
      normalizeHostName(url.host) == normalizeHostName(origin.host) &&
      url.port == origin.port &&
      url.userInfo.isEmpty;

  @override
  String toString() => 'HttpTarget($origin, $addresses)';
}

PortException _rejected(String why) =>
    PortException(PortErrorKind.rejected, 'Ziel nicht erlaubt: $why');

/// Checks [url] as target of a user-defined HTTP call and resolves it.
///
/// Rules (ADR 0011):
/// - only `http`/`https`, no user info, no unusual numeric host spellings
///   (`2130706433`, `0x7f.1`, `127.1`, leading zeros);
/// - loopback and link-local are always rejected unless [allowLoopback]
///   (test mode); unspecified, multicast and reserved addresses always;
/// - private addresses (LAN, Tailscale) only for home-network targets:
///   [homeNetwork] (marked by the user) or a host that is home network by
///   itself ([isHomeNetworkHost]). A public-looking name resolving to a
///   private address is rejected (DNS rebinding);
/// - `http` only for home-network targets whose addresses are all private,
///   otherwise `https`.
///
/// Throws `PortException` (rejected, or unavailable if the name does not
/// resolve). The returned [HttpTarget.addresses] must be used for the
/// connection (see `PinnedHttpToolTransport`).
Future<HttpTarget> checkHttpTarget(
  Uri url, {
  required bool homeNetwork,
  required HostResolver resolve,
  bool allowLoopback = false,
}) async {
  if (!url.isScheme('http') && !url.isScheme('https')) {
    throw _rejected('nur http- und https-Adressen');
  }
  if (url.userInfo.isNotEmpty) throw _rejected('Zugangsdaten in der Adresse');
  final host = normalizeHostName(url.host);
  if (host.isEmpty) throw _rejected('kein Host');
  final literal = _literal(host);
  final localName = isLocalhostName(host);
  final local =
      localName ||
      (literal != null &&
          const {
            AddressScope.loopback,
            AddressScope.linkLocal,
          }.contains(classifyAddress(literal)));
  // Im Test-Modus gilt ein ausdrücklich lokales Ziel als Heimnetz.
  final home =
      homeNetwork || isHomeNetworkHost(host) || (allowLoopback && local);
  final plain = url.isScheme('http');
  if (plain && !home) {
    throw _rejected(
      '„http“ nur im Heimnetz, für „$host“ bitte „https“ verwenden',
    );
  }
  if (localName && !allowLoopback) {
    throw _rejected('lokales Ziel „$host“');
  }
  if (literal == null && host.contains('%')) {
    throw _rejected('IPv6-Zonen-Angabe in „$host“');
  }
  if (literal == null && isNumericHostSpelling(host)) {
    throw _rejected('ungewöhnliche IP-Schreibweise „$host“');
  }
  final List<InternetAddress> addresses;
  if (literal != null) {
    addresses = [literal];
  } else {
    try {
      addresses = await resolve(host);
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
  }
  for (final a in addresses) {
    switch (classifyAddress(a)) {
      case AddressScope.blocked:
        throw _rejected('„$host“ ist keine gültige Zieladresse');
      case AddressScope.loopback || AddressScope.linkLocal:
        if (!allowLoopback) {
          throw _rejected('„$host“ zeigt auf das Gerät selbst oder Link-Local');
        }
        if (!home) {
          throw _rejected(
            '„$host“ zeigt ins lokale Netz – nur für Heimnetz-Ziele',
          );
        }
      case AddressScope.private:
        if (!home) {
          throw _rejected(
            '„$host“ zeigt ins private Netz; als Heimnetz markieren, wenn '
            'das gewollt ist',
          );
        }
      case AddressScope.public:
        if (plain) {
          throw _rejected(
            '„$host“ ist öffentlich erreichbar – bitte „https“ verwenden',
          );
        }
    }
  }
  return HttpTarget(
    origin: Uri.parse(url.origin),
    addresses: addresses,
    homeNetwork: home,
  );
}
