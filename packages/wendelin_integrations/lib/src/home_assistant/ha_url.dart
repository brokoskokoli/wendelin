import 'dart:io';

import '../common/net_scope.dart';
import '../common/port_exception.dart';

final _leadingZeroOctet = RegExp(r'(^|\.)0[0-9]+(\.|$)');

/// Whether [host] may be reached over plain `http`: a private address
/// (RFC 1918, Tailscale `100.64.0.0/10` and `fd7a:…`, loopback), `localhost`,
/// `*.local` (mDNS) or `*.ts.net` (Tailscale MagicDNS). Everything else,
/// also host names that merely resolve to a private address, needs `https`.
bool isPrivateHaHost(String host) {
  var h = normalizeHostName(host);
  if (h.startsWith('[') && h.endsWith(']')) h = h.substring(1, h.length - 1);
  // `010.0.0.1` is 8.0.0.1 for some resolvers (octal) and 10.0.0.1 for
  // others: never private.
  if (_leadingZeroOctet.hasMatch(h)) return false;
  final ip = InternetAddress.tryParse(h);
  if (ip != null) {
    final net = classifyNet(ip);
    // Only plain addresses and IPv4-mapped ones: 6to4 (`2002::/16`), NAT64
    // (`64:ff9b::/96`) and `::a.b.c.d` reach a different, routable host.
    if (net.embedding != Ipv4Embedding.none &&
        net.embedding != Ipv4Embedding.mapped) {
      return false;
    }
    return switch (net.scope) {
      NetScope.privateNetwork ||
      NetScope.carrierNat ||
      NetScope.uniqueLocal ||
      NetScope.loopback => true,
      _ => false,
    };
  }
  if (isNumericHostSpelling(h)) return false;
  return isLocalhostName(h) || h.endsWith('.local') || h.endsWith('.ts.net');
}

/// Address check for the Home Assistant setup.
abstract final class HaUrl {
  /// Parses what the user typed. Without scheme, `http://` is assumed for
  /// private hosts ([isPrivateHaHost]) and `https://` otherwise. Returns the
  /// normalized base URL (no trailing slash, no user info, query or
  /// fragment). Throws [PortException] (`rejected`, German) for plain `http`
  /// to a public host and for malformed input.
  static String parse(String input) {
    var text = input.trim();
    if (text.isEmpty) {
      throw const PortException(PortErrorKind.rejected, 'Adresse fehlt.');
    }
    if (!text.contains('://')) {
      final host = _hostOf(text);
      text =
          '${host != null && isPrivateHaHost(host) ? 'http' : 'https'}://$text';
    }
    final Uri uri;
    try {
      uri = Uri.parse(text);
    } on FormatException {
      throw const PortException(
        PortErrorKind.rejected,
        'Die Adresse ist ungültig.',
      );
    }
    if ((uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const PortException(
        PortErrorKind.rejected,
        'Die Adresse ist ungültig (erwartet: http(s)://Host[:Port]).',
      );
    }
    if (uri.scheme == 'http' && !isPrivateHaHost(uri.host)) {
      throw const PortException(
        PortErrorKind.rejected,
        'Unverschlüsseltes http ist nur im Heimnetz, über Tailscale '
        '(100.x, *.ts.net) oder bei *.local erlaubt. Bitte https benutzen.',
      );
    }
    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return uri.replace(path: path).toString();
  }

  static String? _hostOf(String text) {
    final end = text.indexOf(RegExp(r'[/:]'));
    if (text.startsWith('[')) {
      final close = text.indexOf(']');
      return close < 0 ? null : text.substring(0, close + 1);
    }
    final host = end < 0 ? text : text.substring(0, end);
    return host.isEmpty ? null : host;
  }
}
