import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

const _unreserved =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

/// A random string of [length] unreserved characters (RFC 7636 §4.1), for
/// PKCE verifiers and OAuth `state`. [random] must be `Random.secure()`
/// outside tests.
String randomUnreserved(Random random, int length) => String.fromCharCodes([
  for (var i = 0; i < length; i++)
    _unreserved.codeUnitAt(random.nextInt(_unreserved.length)),
]);

/// PKCE challenge `BASE64URL(SHA256(verifier))` without padding (S256).
String pkceChallenge(String verifier) => base64Url
    .encode(sha256.convert(ascii.encode(verifier)).bytes)
    .replaceAll('=', '');
