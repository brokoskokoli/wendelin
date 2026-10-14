import 'dart:async';

import 'package:wendelin_core/wendelin_core.dart';

import 'gpu_attestation.dart';

/// The GPU check of an `AttestedProvider` (M4 decision 4): when it runs,
/// what it blocks and what it remembers for the session.
///
/// - `before`: the request content leaves the device only after a green
///   check of the model (fail-closed); green is cached per model until
///   [reset] (new attestation).
/// - `after`: the check runs asynchronously after the answer; a failure
///   makes the next request check first, like `before`, until it is green.
final class GpuGate {
  /// Creates the gate; [onResult] receives every finished check (log and
  /// report).
  GpuGate({
    required this.mode,
    required this.verifier,
    required this.timeout,
    required this.onResult,
  });

  /// When the check runs (changeable at runtime).
  GpuCheckMode mode;

  /// NRAS check; `null` = unavailable.
  final GpuAttestationVerifier? verifier;

  /// Upper bound for one check.
  final Duration timeout;

  /// Called with each result.
  final void Function(String model, GpuAttestationResult result) onResult;

  final Map<String, bool> _ok = {};
  bool _needsCheck = false;
  bool _skipOnce = false;

  /// The next [before] lets the request through (user chose „ohne
  /// GPU-Prüfung senden“).
  void allowOnce() => _skipOnce = true;

  /// New attestation: earlier results no longer count.
  void reset() => _ok.clear();

  /// Runs before a request; returns the error that blocks it, or `null`.
  Future<AttestationFailedException?> before(String model) async {
    final v = verifier;
    if (mode == GpuCheckMode.off || v == null) return null;
    if (_skipOnce) {
      _skipOnce = false;
      return null;
    }
    final needed = mode == GpuCheckMode.before
        ? _ok[model] != true
        : _needsCheck;
    if (!needed) return null;
    final result = await _check(v, model);
    if (result.ok) return null;
    return AttestationFailedException(
      'GPU-Prüfung nicht bestanden (${result.detail ?? result.verdict.name}); '
      'Anfrage nicht gesendet',
      stage: 'gpu',
      unavailable:
          result.verdict == GpuVerdict.unreachable ||
          result.verdict == GpuVerdict.timeout,
    );
  }

  /// Runs after a verified answer (mode `after`), without waiting.
  void after(String model) {
    final v = verifier;
    if (mode != GpuCheckMode.after || v == null || _ok[model] == true) return;
    unawaited(_check(v, model));
  }

  Future<GpuAttestationResult> _check(
    GpuAttestationVerifier v,
    String model,
  ) async {
    GpuAttestationResult result;
    try {
      result = await v
          .verify(model: model)
          .timeout(
            timeout,
            onTimeout: () => const GpuAttestationResult(
              GpuVerdict.timeout,
              'Zeitüberschreitung',
            ),
          );
    } on Object {
      result = const GpuAttestationResult(
        GpuVerdict.unreachable,
        'interner Fehler',
      );
    }
    _ok[model] = result.ok;
    _needsCheck = !result.ok;
    onResult(model, result);
    return result;
  }
}
