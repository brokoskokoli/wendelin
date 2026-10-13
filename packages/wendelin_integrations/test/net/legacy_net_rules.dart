// Eingefrorene Kopie der Netzziel-Prüfung vor WP36 a (Stand origin/main
// ec3b1e0, `web/fetch_guard.dart` und `http_tools/http_target.dart`).
// Nur für den Vergleichstest `net_policy_equivalence_test.dart`: Er prüft,
// dass die Policies auf dem gemeinsamen Kern (`common/net_scope.dart`) für
// jede Adresse dasselbe Ergebnis liefern wie vorher. Nicht ändern.
// ignore_for_file: public_member_api_docs, curly_braces_in_flow_control_structures

import 'dart:io';

import 'package:wendelin_integrations/wendelin_integrations.dart'
    show HostResolver, PortErrorKind, PortException;

/// Result of [legacyCheckHttpTarget].
typedef LegacyHttpTarget = ({
  Uri origin,
  List<InternetAddress> addresses,
  bool homeNetwork,
});

const _fgPrivateSuffixes = [
  '.localhost',
  '.local',
  '.internal',
  '.lan',
  '.home.arpa',
];

final _fgNumericHost = RegExp(
  r'^(0x[0-9a-f]*|[0-9]+)(\.(0x[0-9a-f]*|[0-9]+))*$',
);

PortException _fgBlocked(String why) =>
    PortException(PortErrorKind.rejected, 'Adresse nicht erlaubt: $why');

/// Checks that [url] may be fetched: only `http`/`https`, no credentials
/// in the URL, no local or private targets unless the host is in
/// [allowedHosts] (lower-case host names or IP literals).
///
/// Host names are resolved with [resolve] and rejected if any address is
/// private (protects against names pointing into the home network). Throws
/// `PortException(rejected)`.
Future<void> legacyCheckFetchTarget(
  Uri url, {
  required Set<String> allowedHosts,
  required HostResolver resolve,
}) async {
  if (!url.isScheme('http') && !url.isScheme('https')) {
    throw _fgBlocked('nur http- und https-Adressen sind erlaubt');
  }
  if (url.userInfo.isNotEmpty) {
    throw _fgBlocked('Zugangsdaten in der Adresse');
  }
  final host = url.host.toLowerCase();
  if (host.isEmpty) throw _fgBlocked('kein Host');
  if (allowedHosts.contains(host)) return;
  final trimmed = host.endsWith('.')
      ? host.substring(0, host.length - 1)
      : host;
  if (trimmed == 'localhost' || _fgPrivateSuffixes.any(trimmed.endsWith)) {
    throw _fgBlocked('lokales Ziel „$host“');
  }
  final literal = InternetAddress.tryParse(trimmed);
  if (literal != null) {
    if (legacyIsPrivateAddress(literal))
      throw _fgBlocked('privates Netz „$host“');
    return;
  }
  // Numerische Schreibweisen wie 2130706433 oder 0x7f.1 meinen IP-Adressen,
  // die der Resolver unterschiedlich deuten würde.
  if (_fgNumericHost.hasMatch(trimmed)) {
    throw _fgBlocked('ungewöhnliche IP-Schreibweise „$host“');
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
    if (legacyIsPrivateAddress(a)) {
      throw _fgBlocked('„$host“ zeigt in ein privates Netz');
    }
  }
}

/// Whether [address] is loopback, private, link-local, CGNAT, multicast,
/// reserved or unspecified (IPv4 and IPv6, including IPv4-mapped).
bool legacyIsPrivateAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) return _legacyPrivateV4(b);
  if (address.type != InternetAddressType.IPv6 || b.length != 16) return true;
  final allZeroPrefix = b.sublist(0, 10).every((x) => x == 0);
  // ::ffff:a.b.c.d (IPv4-mapped) und ::a.b.c.d (IPv4-kompatibel).
  if (allZeroPrefix &&
      ((b[10] == 0xff && b[11] == 0xff) || (b[10] == 0 && b[11] == 0))) {
    if (b[10] == 0 && b.sublist(12).every((x) => x == 0)) return true; // ::
    if (b[10] == 0 && b.sublist(12, 15).every((x) => x == 0) && b[15] == 1) {
      return true; // ::1
    }
    return _legacyPrivateV4(b.sublist(12));
  }
  // 64:ff9b::/96 (NAT64) trägt eine IPv4-Adresse.
  if (b[0] == 0 && b[1] == 0x64 && b[2] == 0xff && b[3] == 0x9b) {
    return _legacyPrivateV4(b.sublist(12));
  }
  if ((b[0] & 0xfe) == 0xfc) return true; // fc00::/7 ULA
  if (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) return true; // fe80::/10
  if (b[0] == 0xfe && (b[1] & 0xc0) == 0xc0) return true; // fec0::/10
  if (b[0] == 0xff) return true; // Multicast
  return false;
}

bool _legacyPrivateV4(List<int> b) {
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

/// Network scope of an IP address.

enum LegacyScope {
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

/// The [LegacyScope] of [address]; IPv4 embedded in IPv6 (mapped,
/// compatible, NAT64 `64:ff9b::/96`, 6to4 `2002::/16`) is classified by
/// its IPv4 part.
LegacyScope legacyClassifyAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (address.type == InternetAddressType.IPv4 && b.length == 4) {
    return _classifyV4(b);
  }
  if (address.type != InternetAddressType.IPv6 || b.length != 16) {
    return LegacyScope.blocked;
  }
  final zeroPrefix = b.sublist(0, 10).every((x) => x == 0);
  if (zeroPrefix && b[10] == 0 && b[11] == 0) {
    if (b.sublist(12, 15).every((x) => x == 0)) {
      if (b[15] == 0) return LegacyScope.blocked; // ::
      if (b[15] == 1) return LegacyScope.loopback; // ::1
    }
    return _classifyV4(b.sublist(12)); // ::a.b.c.d
  }
  if (zeroPrefix && b[10] == 0xff && b[11] == 0xff) {
    return _classifyV4(b.sublist(12)); // ::ffff:a.b.c.d
  }
  if (b.sublist(0, 8).every((x) => x == 0) &&
      b[8] == 0xff &&
      b[9] == 0xff &&
      b[10] == 0 &&
      b[11] == 0) {
    return _classifyV4(b.sublist(12)); // ::ffff:0:a.b.c.d (SIIT)
  }
  if (b[0] == 0 && b[1] == 0x64 && b[2] == 0xff && b[3] == 0x9b) {
    // 64:ff9b::/96 (NAT64) und 64:ff9b:1::/48 (lokales NAT64).
    return _classifyV4(b.sublist(12));
  }
  if (b[0] == 0x01 && b.sublist(1, 8).every((x) => x == 0)) {
    return LegacyScope.blocked; // 100::/64 (Discard)
  }
  if (b[0] == 0x20 && b[1] == 0x02) return _classifyV4(b.sublist(2, 6));
  if ((b[0] & 0xfe) == 0xfc) return LegacyScope.private; // fc00::/7
  if (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) return LegacyScope.linkLocal;
  if (b[0] == 0xfe && (b[1] & 0xc0) == 0xc0) return LegacyScope.private;
  if (b[0] == 0xff) return LegacyScope.blocked; // Multicast
  return LegacyScope.public;
}

LegacyScope _classifyV4(List<int> b) {
  final a0 = b[0];
  final a1 = b[1];
  if (a0 == 127) return LegacyScope.loopback;
  if (a0 == 169 && a1 == 254) return LegacyScope.linkLocal;
  if (a0 == 10 ||
      (a0 == 172 && a1 >= 16 && a1 <= 31) ||
      (a0 == 192 && a1 == 168) ||
      (a0 == 100 && a1 >= 64 && a1 <= 127)) {
    return LegacyScope.private;
  }
  if (a0 == 0 ||
      (a0 == 192 && a1 == 0 && b[2] == 0) ||
      (a0 == 198 && (a1 == 18 || a1 == 19)) ||
      a0 >= 224) {
    return LegacyScope.blocked;
  }
  return LegacyScope.public;
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
bool legacyIsHomeNetworkHost(String host) {
  final h = _trimDot(host);
  final literal = _literal(h);
  if (literal != null)
    return legacyClassifyAddress(literal) == LegacyScope.private;
  return _homeSuffixes.any(h.endsWith);
}

InternetAddress? _literal(String host) {
  if (host.contains(':')) return InternetAddress.tryParse(host);
  return _dottedQuad.hasMatch(host) ? InternetAddress.tryParse(host) : null;
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
///   itself ([legacyIsHomeNetworkHost]). A public-looking name resolving to a
///   private address is rejected (DNS rebinding);
/// - `http` only for home-network targets whose addresses are all private,
///   otherwise `https`.
///
/// Throws `PortException` (rejected, or unavailable if the name does not
/// resolve). The returned [HttpTarget.addresses] must be used for the
/// connection (see `PinnedHttpToolTransport`).
Future<LegacyHttpTarget> legacyCheckHttpTarget(
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
            LegacyScope.loopback,
            LegacyScope.linkLocal,
          }.contains(legacyClassifyAddress(literal)));
  // Im Test-Modus gilt ein ausdrücklich lokales Ziel als Heimnetz.
  final home =
      homeNetwork || legacyIsHomeNetworkHost(host) || (allowLoopback && local);
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
    switch (legacyClassifyAddress(a)) {
      case LegacyScope.blocked:
        throw _rejected('„$host“ ist keine gültige Zieladresse');
      case LegacyScope.loopback || LegacyScope.linkLocal:
        if (!allowLoopback) {
          throw _rejected('„$host“ zeigt auf das Gerät selbst oder Link-Local');
        }
        if (!home) {
          throw _rejected(
            '„$host“ zeigt ins lokale Netz – nur für Heimnetz-Ziele',
          );
        }
      case LegacyScope.private:
        if (!home) {
          throw _rejected(
            '„$host“ zeigt ins private Netz; als Heimnetz markieren, wenn '
            'das gewollt ist',
          );
        }
      case LegacyScope.public:
        if (plain) {
          throw _rejected(
            '„$host“ ist öffentlich erreichbar – bitte „https“ verwenden',
          );
        }
    }
  }
  return (
    origin: Uri.parse(url.origin),
    addresses: addresses,
    homeNetwork: home,
  );
}
