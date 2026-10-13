// Zielprüfung der HTTP-Tools (SSRF, DNS-Rebinding), siehe ADR 0011.

import 'dart:io';

import 'package:meta/meta.dart';

import '../common/port_exception.dart';
import '../web/fetch_guard.dart' show HostResolver;

/// Network scope of an IP address.
enum AddressScope {
  /// Routable on the internet.
  public,

  /// Private network: RFC 1918, CGNAT/Tailscale `100.64.0.0/10`, IPv6 ULA
  /// `fc00::/7`, site-local `fec0::/10`.
  private,

  /// Loopback (`127.0.0.0/8`, `::1`).
  loopback,

  /// Link-local (`169.254.0.0/16`, `fe80::/10`).
  linkLocal,

  /// Never a valid target: unspecified, `0.0.0.0/8`, multicast, broadcast,
  /// reserved, benchmark and IETF-protocol ranges.
  blocked,
}

/// The [AddressScope] of [address]; IPv4 embedded in IPv6 (mapped,
/// compatible, NAT64 `64:ff9b::/96`, 6to4 `2002::/16`) is classified by
/// its IPv4 part.
AddressScope classifyAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (address.type == InternetAddressType.IPv4 && b.length == 4) {
    return _classifyV4(b);
  }
  if (address.type != InternetAddressType.IPv6 || b.length != 16) {
    return AddressScope.blocked;
  }
  final zeroPrefix = b.sublist(0, 10).every((x) => x == 0);
  if (zeroPrefix && b[10] == 0 && b[11] == 0) {
    if (b.sublist(12, 15).every((x) => x == 0)) {
      if (b[15] == 0) return AddressScope.blocked; // ::
      if (b[15] == 1) return AddressScope.loopback; // ::1
    }
    return _classifyV4(b.sublist(12)); // ::a.b.c.d
  }
  if (zeroPrefix && b[10] == 0xff && b[11] == 0xff) {
    return _classifyV4(b.sublist(12)); // ::ffff:a.b.c.d
  }
  if (b[0] == 0 && b[1] == 0x64 && b[2] == 0xff && b[3] == 0x9b) {
    return _classifyV4(b.sublist(12)); // NAT64
  }
  if (b[0] == 0x20 && b[1] == 0x02) return _classifyV4(b.sublist(2, 6));
  if ((b[0] & 0xfe) == 0xfc) return AddressScope.private; // fc00::/7
  if (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) return AddressScope.linkLocal;
  if (b[0] == 0xfe && (b[1] & 0xc0) == 0xc0) return AddressScope.private;
  if (b[0] == 0xff) return AddressScope.blocked; // Multicast
  return AddressScope.public;
}

AddressScope _classifyV4(List<int> b) {
  final a0 = b[0];
  final a1 = b[1];
  if (a0 == 127) return AddressScope.loopback;
  if (a0 == 169 && a1 == 254) return AddressScope.linkLocal;
  if (a0 == 10 ||
      (a0 == 172 && a1 >= 16 && a1 <= 31) ||
      (a0 == 192 && a1 == 168) ||
      (a0 == 100 && a1 >= 64 && a1 <= 127)) {
    return AddressScope.private;
  }
  if (a0 == 0 ||
      (a0 == 192 && a1 == 0 && b[2] == 0) ||
      (a0 == 198 && (a1 == 18 || a1 == 19)) ||
      a0 >= 224) {
    return AddressScope.blocked;
  }
  return AddressScope.public;
}

const _homeSuffixes = [
  '.local',
  '.lan',
  '.home',
  '.home.arpa',
  '.internal',
  '.ts.net',
];

final _numericHost = RegExp(r'^(0x[0-9a-f]*|[0-9]+)(\.(0x[0-9a-f]*|[0-9]+))*$');
final _dottedQuad = RegExp(
  r'^(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})$',
);

String _trimDot(String host) {
  final h = host.toLowerCase();
  return h.endsWith('.') ? h.substring(0, h.length - 1) : h;
}

/// Whether [host] names a home-network target by itself: a private IP
/// literal (RFC 1918, Tailscale `100.64.0.0/10`, ULA) or a name ending in
/// `.local`, `.lan`, `.home`, `.home.arpa`, `.internal` or `.ts.net`.
bool isHomeNetworkHost(String host) {
  final h = _trimDot(host);
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
      _trimDot(url.host) == _trimDot(origin.host) &&
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
  final host = _trimDot(url.host);
  if (host.isEmpty) throw _rejected('kein Host');
  final literal = _literal(host);
  final localName = host == 'localhost' || host.endsWith('.localhost');
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
  if (literal == null && _numericHost.hasMatch(host)) {
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
