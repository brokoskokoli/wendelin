import 'dart:async';

import 'package:wendelin_core/wendelin_core.dart';

import 'gpu_attestation.dart';

/// The GPU check of an `AttestedProvider` (M4 decision 4): when it runs,
/// what it blocks and what it remembers for the session.
///
/// - The **local nonce binding** of the GPU evidence ([GpuAttestationVerifier.verifyLocal],
///   no call to NVIDIA) runs in every mode, once per model and session
///   before the first request; a failure blocks the request.
/// - `before`: the request content leaves the device only after a green
///   NRAS check of the model (fail-closed); green is cached per model until
///   [reset] (new attestation).
/// - `after`: the NRAS check runs asynchronously after the answer; a
///   failure makes the next request of **that model** check first, like
///   `before`, until it is green. The failure also reaches subscribers of
///   `AttestedProvider.reports` (see there).
/// - `off`: no call to NVIDIA.
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

  /// Called with each result; [nras] tells whether NVIDIA was asked (full
  /// check) or only the local nonce binding ran.
  final void Function(String model, GpuAttestationResult result, bool nras)
  onResult;

  final Map<String, bool> _ok = {};
  final Set<String> _localOk = {};
  final Set<String> _needsCheck = {};
  bool _skipOnce = false;

  /// The next [before] lets the request through (user chose „ohne
  /// GPU-Prüfung senden“).
  void allowOnce() => _skipOnce = true;

  /// New attestation: earlier results no longer count.
  void reset() {
    _ok.clear();
    _localOk.clear();
  }

  /// Runs before a request; returns the error that blocks it, or `null`.
  Future<AttestationFailedException?> before(String model) async {
    final v = verifier;
    if (v == null) return null;
    if (_skipOnce) {
      _skipOnce = false;
      return null;
    }
    final full = switch (mode) {
      GpuCheckMode.before => _ok[model] != true,
      GpuCheckMode.after => _needsCheck.contains(model),
      GpuCheckMode.off => false,
    };
    if (!full && _localOk.contains(model)) return null;
    final result = full ? await _check(v, model) : await _checkLocal(v, model);
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
    if (result.ok) {
      _localOk.add(model);
      _needsCheck.remove(model);
    } else {
      _needsCheck.add(model);
    }
    onResult(model, result, true);
    return result;
  }

  Future<GpuAttestationResult> _checkLocal(
    GpuAttestationVerifier v,
    String model,
  ) async {
    GpuAttestationResult result;
    try {
      result = await v
          .verifyLocal(model: model)
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
    if (result.ok) _localOk.add(model);
    onResult(model, result, false);
    return result;
  }
}
