import 'dart:async';

import 'gpu_attestation.dart';

/// [GpuAttestationVerifier] for tests: answers with [result] (change it
/// between calls), optionally after [gate] completes (to model a slow NRAS).
final class FakeGpuAttestationVerifier implements GpuAttestationVerifier {
  /// Creates the fake.
  FakeGpuAttestationVerifier([
    this.result = const GpuAttestationResult(GpuVerdict.verified),
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
