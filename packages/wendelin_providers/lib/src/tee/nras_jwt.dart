import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

/// Why an NRAS token is not accepted ([NrasJwtException.reason]).
abstract final class NrasJwtReason {
  /// Not a three-part JWT, or header/claims are not JSON.
  static const malformed = 'jwt_malformed';

  /// `alg` is not `ES384` (also `none`).
  static const algorithm = 'jwt_alg';

  /// No key with the token's `kid` (also after a refetch of the JWKS).
  static const unknownKey = 'jwt_unknown_kid';

  /// The ES384 signature does not verify.
  static const signature = 'jwt_signature';

  /// `exp`/`nbf`/`iat` do not allow the token now.
  static const expired = 'jwt_expired';

  /// `iss` is not NVIDIA's NRAS.
  static const issuer = 'jwt_issuer';

  /// The JWKS could not be fetched or read.
  static const jwksUnavailable = 'jwks_unavailable';
}

/// A token that must not be trusted. [reason] is a [NrasJwtReason].
final class NrasJwtException implements Exception {
  /// Creates the exception.
  const NrasJwtException(this.reason);

  /// Secret-free category.
  final String reason;

  /// Whether the cause is the network (JWKS), not the token.
  bool get unavailable => reason == NrasJwtReason.jwksUnavailable;

  @override
  String toString() => 'NrasJwtException: $reason';
}

/// ECDSA over NIST P-384 (verification only, public data: no
/// constant-time arithmetic needed). Pure Dart on [BigInt]; one verification
/// takes a few milliseconds, the NRAS check happens once per session.
abstract final class P384 {
  static final _p = BigInt.parse(
    'fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe'
    'ffffffff0000000000000000ffffffff',
    radix: 16,
  );
  static final _n = BigInt.parse(
    'ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf'
    '581a0db248b0a77aecec196accc52973',
    radix: 16,
  );
  static final _b = BigInt.parse(
    'b3312fa7e23ee7e4988e056be3f82d19181d9c6efe8141120314088f5013875a'
    'c656398d8a2ed19d2a85c8edd3ec2aef',
    radix: 16,
  );
  static final _gx = BigInt.parse(
    'aa87ca22be8b05378eb1c71ef320ad746e1d3b628ba79b9859f741e082542a38'
    '5502f25dbf55296c3a545e3872760ab7',
    radix: 16,
  );
  static final _gy = BigInt.parse(
    '3617de4a96262c6f5d9e98bf9292dc29f8f41dbd289a147ce9da3113b5f0b8c0'
    '0a60b1ce1d7e819d7a431d7c90ea0e5f',
    radix: 16,
  );

  /// Whether (x, y) is a point of the curve.
  static bool onCurve(BigInt x, BigInt y) {
    if (x < BigInt.zero || x >= _p || y < BigInt.zero || y >= _p) return false;
    final lhs = (y * y) % _p;
    final rhs = (x * x * x - BigInt.from(3) * x + _b) % _p;
    return lhs == rhs;
  }

  // Points are (x, y) pairs or null for the point at infinity.
  static (BigInt, BigInt)? _add((BigInt, BigInt)? a, (BigInt, BigInt)? b) {
    if (a == null) return b;
    if (b == null) return a;
    final BigInt lambda;
    if (a.$1 == b.$1) {
      if ((a.$2 + b.$2) % _p == BigInt.zero) return null;
      lambda =
          ((BigInt.from(3) * a.$1 * a.$1 - BigInt.from(3)) *
              (BigInt.two * a.$2).modInverse(_p)) %
          _p;
    } else {
      lambda = ((b.$2 - a.$2) * (b.$1 - a.$1).modInverse(_p)) % _p;
    }
    final x = (lambda * lambda - a.$1 - b.$1) % _p;
    final y = (lambda * (a.$1 - x) - a.$2) % _p;
    return (x, y);
  }

  static (BigInt, BigInt)? _mul(BigInt k, (BigInt, BigInt) point) {
    (BigInt, BigInt)? result;
    (BigInt, BigInt)? addend = point;
    var rest = k;
    while (rest > BigInt.zero) {
      if (rest.isOdd) result = _add(result, addend);
      addend = _add(addend, addend);
      rest >>= 1;
    }
    return result;
  }

  static BigInt _int(List<int> bytes) {
    var v = BigInt.zero;
    for (final b in bytes) {
      v = (v << 8) | BigInt.from(b);
    }
    return v;
  }

  /// Verifies the raw (r || s, 96 bytes) ECDSA [signature] over the SHA-384
  /// of [message] for the public key ([x], [y]).
  static bool verify({
    required BigInt x,
    required BigInt y,
    required List<int> message,
    required List<int> signature,
  }) {
    if (signature.length != 96 || !onCurve(x, y)) return false;
    final r = _int(signature.sublist(0, 48));
    final s = _int(signature.sublist(48));
    if (r <= BigInt.zero || r >= _n || s <= BigInt.zero || s >= _n) {
      return false;
    }
    final e = _int(crypto.sha384.convert(message).bytes);
    final w = s.modInverse(_n);
    final u1 = (e * w) % _n;
    final u2 = (r * w) % _n;
    final point = _add(_mul(u1, (_gx, _gy)), _mul(u2, (x, y)));
    return point != null && point.$1 % _n == r;
  }
}

/// A public NVIDIA signing key from the JWKS.
final class NrasKey {
  /// Creates a key.
  const NrasKey(this.x, this.y);

  /// Affine coordinates on P-384.
  final BigInt x;

  /// Affine y.
  final BigInt y;
}

BigInt _b64Int(Object? v) {
  final bytes = base64Url.decode(base64Url.normalize(v! as String));
  var r = BigInt.zero;
  for (final b in bytes) {
    r = (r << 8) | BigInt.from(b);
  }
  return r;
}

/// The public keys NVIDIA signs NRAS tokens with (JWKS) with a cache:
/// refetched when older than [maxAge] or when a `kid` is unknown (NVIDIA
/// rotates keys every few hours; at most once per [minRefetch], so a forged
/// `kid` cannot turn into a flood). The JWKS comes over TLS from NVIDIA; a
/// failed fetch is [NrasJwtReason.jwksUnavailable] (fail-closed).
final class NrasJwks {
  /// Creates the key source.
  NrasJwks({
    required this._client,
    this.url = 'https://nras.attestation.nvidia.com/.well-known/jwks.json',
    this.timeout = const Duration(seconds: 10),
    this.maxAge = const Duration(hours: 1),
    this.minRefetch = const Duration(seconds: 30),
    DateTime Function()? clock,
    Map<String, NrasKey> seed = const {},
  }) : _clock = clock ?? DateTime.now,
       _keys = {...seed};

  /// JWKS endpoint.
  final String url;

  /// Upper bound for the fetch.
  final Duration timeout;

  /// How long a fetched set counts without an unknown `kid`.
  final Duration maxAge;

  /// Minimum gap between two fetches.
  final Duration minRefetch;

  final http.Client _client;
  final DateTime Function() _clock;
  final Map<String, NrasKey> _keys;
  DateTime? _fetchedAt;
  Future<void>? _inflight;

  /// The key for [kid]; fetches the set when it is unknown or stale.
  /// Throws [NrasJwtException] (`jwt_unknown_kid`, `jwks_unavailable`).
  Future<NrasKey> keyFor(String kid) async {
    final known = _keys[kid];
    final at = _fetchedAt;
    final fresh = at != null && _clock().difference(at) < maxAge;
    if (known != null && (fresh || at == null)) return known;
    final recent = at != null && _clock().difference(at) < minRefetch;
    if (!recent) {
      await (_inflight ??= _fetch().whenComplete(() => _inflight = null));
    }
    final key = _keys[kid];
    if (key == null) throw const NrasJwtException(NrasJwtReason.unknownKey);
    return key;
  }

  Future<void> _fetch() async {
    try {
      final response = await _client.get(Uri.parse(url)).timeout(timeout);
      if (response.statusCode != 200) {
        throw const NrasJwtException(NrasJwtReason.jwksUnavailable);
      }
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      final keys = <String, NrasKey>{};
      for (final k in (json as Map<String, Object?>)['keys']! as List) {
        final m = k as Map<String, Object?>;
        if (m['kty'] != 'EC' || m['crv'] != 'P-384') continue;
        final key = NrasKey(_b64Int(m['x']), _b64Int(m['y']));
        if (P384.onCurve(key.x, key.y)) keys[m['kid']! as String] = key;
      }
      if (keys.isEmpty) {
        throw const NrasJwtException(NrasJwtReason.jwksUnavailable);
      }
      _keys
        ..clear()
        ..addAll(keys);
      _fetchedAt = _clock();
    } on NrasJwtException {
      rethrow;
    } on Object {
      throw const NrasJwtException(NrasJwtReason.jwksUnavailable);
    }
  }
}

/// Checks an NRAS token and returns its claims; throws [NrasJwtException].
abstract interface class NrasTokenChecker {
  /// Claims of [token] if it is trustworthy (signature, issuer, validity).
  Future<Map<String, Object?>> verify(String token);
}

/// Checks NRAS tokens (JWT, ES384) against [NrasJwks].
final class NrasTokenVerifier implements NrasTokenChecker {
  /// Creates the verifier.
  NrasTokenVerifier({
    required this.jwks,
    DateTime Function()? clock,
    this.skew = const Duration(minutes: 2),
    this.issuer = 'https://nras.attestation.nvidia.com',
  }) : _clock = clock ?? DateTime.now;

  /// Key source.
  final NrasJwks jwks;

  /// Accepted issuer.
  final String issuer;

  /// Clock tolerance for `nbf`/`iat`/`exp`.
  final Duration skew;

  final DateTime Function() _clock;

  /// Returns the claims of [token] if signature, issuer and validity period
  /// hold; otherwise throws [NrasJwtException]. Claims are only ever read
  /// from this result, never from an unverified token.
  @override
  Future<Map<String, Object?>> verify(String token) async {
    final parts = token.split('.');
    if (parts.length != 3) {
      throw const NrasJwtException(NrasJwtReason.malformed);
    }
    final Map<String, Object?> header;
    final Map<String, Object?> claims;
    final Uint8List signature;
    try {
      header = _json(parts[0]);
      claims = _json(parts[1]);
      signature = Uint8List.fromList(
        base64Url.decode(base64Url.normalize(parts[2])),
      );
    } on Object {
      throw const NrasJwtException(NrasJwtReason.malformed);
    }
    if (header['alg'] != 'ES384') {
      throw const NrasJwtException(NrasJwtReason.algorithm);
    }
    final kid = header['kid'];
    if (kid is! String) throw const NrasJwtException(NrasJwtReason.malformed);
    final key = await jwks.keyFor(kid);
    final ok = P384.verify(
      x: key.x,
      y: key.y,
      message: ascii.encode('${parts[0]}.${parts[1]}'),
      signature: signature,
    );
    if (!ok) throw const NrasJwtException(NrasJwtReason.signature);
    if (claims['iss'] != issuer) {
      throw const NrasJwtException(NrasJwtReason.issuer);
    }
    final now = _clock().millisecondsSinceEpoch ~/ 1000;
    final slack = skew.inSeconds;
    final exp = claims['exp'];
    if (exp is! num || now > exp + slack) {
      throw const NrasJwtException(NrasJwtReason.expired);
    }
    for (final name in ['nbf', 'iat']) {
      final v = claims[name];
      if (v != null && (v is! num || v > now + slack)) {
        throw const NrasJwtException(NrasJwtReason.expired);
      }
    }
    return claims;
  }

  static Map<String, Object?> _json(String part) =>
      jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(part))))
          as Map<String, Object?>;
}
