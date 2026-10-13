// Eingefrorene Kopie der Host-Prüfung von net_policy.dart vor WP36 b.
// Nur für net_policy_equivalence_test.dart. Nicht ändern.
// ignore_for_file: public_member_api_docs
import 'dart:io';

const _legacyHomeSuffixes = ['.ts.net', '.local', '.home.arpa'];

/// Whether [host] is `localhost` or a loopback literal.
bool legacyIsLoopbackHost(String host) {
  final h = _legacyTrim(host);
  if (h == 'localhost' || h.endsWith('.localhost')) return true;
  return InternetAddress.tryParse(h)?.isLoopback ?? false;
}

/// Whether [host] lies in the home network as defined by [checkServerUrl].
bool legacyIsHomeNetworkHost(String host) {
  final h = _legacyTrim(host);
  if (legacyIsLoopbackHost(h)) return true;
  if (_legacyHomeSuffixes.any(h.endsWith)) return true;
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

String _legacyTrim(String host) {
  var h = host.toLowerCase();
  if (h.startsWith('[') && h.endsWith(']')) h = h.substring(1, h.length - 1);
  if (h.endsWith('.')) h = h.substring(0, h.length - 1);
  return h;
}
