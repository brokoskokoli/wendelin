import 'dart:io';

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
  if (h == 'localhost' || h.endsWith('.localhost')) return true;
  return InternetAddress.tryParse(h)?.isLoopback ?? false;
}

/// Whether [host] lies in the home network as defined by [checkServerUrl].
bool isHomeNetworkHost(String host) {
  final h = _trim(host);
  if (isLoopbackHost(h)) return true;
  if (_homeSuffixes.any(h.endsWith)) return true;
  final address = InternetAddress.tryParse(h);
  if (address == null) return false;
  final b = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    return b[0] == 10 || // 10/8 (auch Emulator 10.0.2.2)
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || // 172.16/12
        (b[0] == 192 && b[1] == 168) || // 192.168/16
        (b[0] == 100 && b[1] >= 64 && b[1] <= 127); // 100.64/10 Tailscale
  }
  return (b[0] & 0xfe) == 0xfc || // fc00::/7 ULA (Tailscale fd7a:…)
      (b[0] == 0xfe && (b[1] & 0xc0) == 0x80); // fe80::/10
}

String _trim(String host) {
  var h = host.toLowerCase();
  if (h.startsWith('[') && h.endsWith(']')) h = h.substring(1, h.length - 1);
  if (h.endsWith('.')) h = h.substring(0, h.length - 1);
  return h;
}
