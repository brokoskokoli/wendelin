import 'dart:async';
import 'dart:convert';

import 'gpu_attestation.dart';
import 'nras_jwt.dart';

/// [GpuAttestationVerifier] for tests: answers with [result] (change it
/// between calls), optionally after [gate] completes (to model a slow NRAS).
final class FakeGpuAttestationVerifier implements GpuAttestationVerifier {
  /// Creates the fake.
  FakeGpuAttestationVerifier([
    this.result = const GpuAttestationResult(
      GpuVerdict.verified,
      null,
      null,
      true,
    ),
  ]);

  /// Answer of the next calls.
  GpuAttestationResult result;

  /// If set, calls wait for it.
  Completer<void>? gate;

  /// Answer of the local nonce check ([verifyLocal]); default verified.
  GpuAttestationResult localResult = const GpuAttestationResult(
    GpuVerdict.verified,
  );

  /// Models asked for, in order (full checks).
  final List<String> calls = [];

  /// Models of the local nonce checks, in order.
  final List<String> localCalls = [];

  @override
  Future<GpuAttestationResult> verifyLocal({required String model}) async {
    localCalls.add(model);
    return localResult;
  }

  @override
  Future<GpuAttestationResult> verify({required String model}) async {
    calls.add(model);
    await gate?.future;
    return result;
  }
}

/// [NrasTokenChecker] for tests: reads the claims **without** checking the
/// signature, or throws [NrasJwtException] with [failWith].
final class FakeNrasTokenChecker implements NrasTokenChecker {
  /// Creates the fake.
  FakeNrasTokenChecker({this.failWith});

  /// If set, every token is rejected with this [NrasJwtReason].
  String? failWith;

  /// Tokens asked about, in order.
  final List<String> seen = [];

  @override
  Future<Map<String, Object?>> verify(String token) async {
    seen.add(token);
    final reason = failWith;
    if (reason != null) throw NrasJwtException(reason);
    return jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
    ) as Map<String, Object?>;
  }
}
