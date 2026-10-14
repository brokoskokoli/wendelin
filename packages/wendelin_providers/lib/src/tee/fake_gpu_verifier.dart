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

  /// Models asked for, in order.
  final List<String> calls = [];

  @override
  Future<GpuAttestationResult> verify({required String model}) async {
    calls.add(model);
    await gate?.future;
    return result;
  }
}
