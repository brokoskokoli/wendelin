import 'dart:io';

import 'package:wendelin_integrations/wendelin_integrations.dart'
    show
        Ipv4Embedding,
        NetScope,
        classifyNet,
        isLocalhostName,
        normalizeHostName;

import 'errors.dart';

// Netzziel-Regeln (ADR 0010): https überall, http nur ins Heimnetz.

const _homeSuffixes = ['.ts.net', '.local', '.home.arpa'];

McpException _rejected(String why) =>
    McpException(McpErrorKind.rejected, 'Adresse nicht erlaubt: $why');

/// Checks that the MCP server [url] may be contacted.
///
/// - `https` to any host;
/// - `http` only to private or home-network targets
///   ([isHomeNetworkHost]): RFC 1918, Tailscale CGNAT `100.64.0.0/10`,
///   `*.ts.net`, `*.local`, `*.home.arpa`, loopback, the emulator host
///   `10.0.2.2`, IPv6 ULA/link-local; plain text into the internet is
///   refused;
/// - no credentials in the URL (`user:pass@`), a host is required.
///
/// Throws [McpException] with [McpErrorKind.rejected].
void checkServerUrl(Uri url) {
  _common(url);
  if (url.isScheme('https')) return;
  if (url.isScheme('http')) {
    if (isHomeNetworkHost(url.host)) return;
    throw _rejected(
      'unverschlüsseltes http nur im Heimnetz (Tailscale, LAN), '
      'sonst https verwenden',
    );
  }
  throw _rejected('nur http- und https-Adressen sind erlaubt');
}

/// Checks an OAuth endpoint (metadata, authorization, token, registration):
/// `https` only; `http` solely for loopback (`localhost`, `127.0.0.1`,
/// `::1`, used by tests). No credentials in the URL.
void checkOAuthUrl(Uri url) {
  _common(url);
  if (url.isScheme('https')) return;
  if (url.isScheme('http') && isLoopbackHost(url.host)) return;
  throw _rejected('OAuth-Endpunkte nur über https');
}

void _common(Uri url) {
  if (url.userInfo.isNotEmpty) {
    throw _rejected('Zugangsdaten in der Adresse');
  }
  if (url.host.isEmpty) throw _rejected('kein Host');
}

/// Whether [a] and [b] have the same origin (scheme, host, port).
bool sameOrigin(Uri a, Uri b) =>
    a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
    a.host.toLowerCase() == b.host.toLowerCase() &&
    a.port == b.port;

/// Checks that a redirect from [from] to [to] stays on the same origin.
void checkRedirect(Uri from, Uri to) {
  if (!sameOrigin(from, to)) {
    throw _rejected('Weiterleitung auf einen anderen Server ($to)');
  }
}

/// Whether [host] is `localhost` or a loopback literal.
bool isLoopbackHost(String host) {
  final h = _trim(host);
  if (isLocalhostName(h)) return true;
  final address = InternetAddress.tryParse(h);
  return address != null && _isNativeLoopback(address);
}

/// Whether [host] lies in the home network as defined by [checkServerUrl].
bool isHomeNetworkHost(String host) {
  final h = _trim(host);
  if (isLoopbackHost(h)) return true;
  if (_homeSuffixes.any(h.endsWith)) return true;
  final address = InternetAddress.tryParse(h);
  if (address == null) return false;
  final c = classifyNet(address);
  if (c.embedding != Ipv4Embedding.none) return false;
  return switch (c.scope) {
    NetScope.privateNetwork ||
    NetScope.carrierNat ||
    NetScope.uniqueLocal => true,
    // 169.254/16 bleibt wie bisher ausgeschlossen, nur fe80::/10 zählt.
    NetScope.linkLocal => address.type == InternetAddressType.IPv6,
    _ => false,
  };
}

// Loopback nur als 127/8 oder ::1, nicht als eingebettetes IPv4.
bool _isNativeLoopback(InternetAddress address) {
  final c = classifyNet(address);
  return c.scope == NetScope.loopback && c.embedding == Ipv4Embedding.none;
}

String _trim(String host) {
  final h = host.toLowerCase();
  return normalizeHostName(
    h.startsWith('[') && h.endsWith(']') ? h.substring(1, h.length - 1) : h,
  );
}
