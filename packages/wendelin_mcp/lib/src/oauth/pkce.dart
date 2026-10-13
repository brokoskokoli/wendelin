import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

const _unreserved =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

/// A random string of [length] unreserved characters (RFC 7636 §4.1) from
/// [random] (use `Random.secure()` outside tests).
String randomToken(Random random, [int length = 64]) => String.fromCharCodes([
  for (var i = 0; i < length; i++)
    _unreserved.codeUnitAt(random.nextInt(_unreserved.length)),
]);

/// PKCE code challenge for [verifier] with method `S256`:
/// `BASE64URL(SHA256(verifier))` without padding (RFC 7636 §4.2).
String s256Challenge(String verifier) => base64Url
    .encode(sha256.convert(ascii.encode(verifier)).bytes)
    .replaceAll('=', '');
