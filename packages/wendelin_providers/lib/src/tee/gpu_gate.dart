import 'dart:async';

import 'package:wendelin_core/wendelin_core.dart';

import 'gpu_attestation.dart';

/// The GPU check of an `AttestedProvider` (M4 decision 4): when it runs,
/// what it blocks and what it remembers for the session.
///
/// - `off`: no GPU check at all, no fetch of the evidence and no call to
///   NVIDIA (WP77; the session attestation is what protects the request).
/// - In `before` and `after` the **local nonce binding** of the GPU evidence
///   ([GpuAttestationVerifier.verifyLocal], no call to NVIDIA) runs once per
///   model and session before the first request, **in parallel to the
///   session attestation** ([AttestedProvider] starts both); a failure
///   blocks the request.
/// - `before`: the request content leaves the device only after a green
///   NRAS check of the model (fail-closed); green is cached per model until
///   [reset] (new attestation).
/// - `after`: the NRAS check runs asynchronously after the answer; a
///   failure makes the next request of **that model** check first, like
///   `before`, until it is green. The failure also reaches subscribers of
///   `AttestedProvider.reports` (see there).
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

  final Map<String, Future<GpuAttestationResult>> _inflight = {};
  final Map<String, bool> _ok = {};
  final Set<String> _localOk = {};
  final Set<String> _needsCheck = {};

  /// Models whose provider delivers no GPU evidence at all (this session):
  /// NVIDIA cannot check what is not there, so there is nothing to retry.
  final Map<String, GpuAttestationResult> _noEvidence = {};
  bool _skipOnce = false;

  /// The next [before] lets the request through (user chose „ohne
  /// GPU-Prüfung senden“).
  void allowOnce() => _skipOnce = true;

  /// Takes over the results of [other] (same session, rebuilt provider).
  void adopt(GpuGate other) {
    _ok.addAll(other._ok);
    _localOk.addAll(other._localOk);
    _needsCheck.addAll(other._needsCheck);
    _noEvidence.addAll(other._noEvidence);
  }

  /// New attestation: earlier results no longer count.
  void reset() {
    _ok.clear();
    _localOk.clear();
    _noEvidence.clear();
  }

  /// Whether the provider delivers GPU evidence for [model]: `true`/`false`,
  /// `null` if that could not be found out (no verifier, network). Local
  /// part only, independent of [mode]; used by the setup.
  Future<bool?> hasEvidence(String model) async {
    final r = await localCheck(model);
    if (r == null) return null;
    if (r.ok) return true;
    return r.category == GpuReason.noEvidence ? false : null;
  }

  /// The local part of the GPU check (evidence present, our nonce in it);
  /// `null` without verifier. A real failure (e.g. nonce mismatch) is not
  /// „no evidence“ and must stay visible (setup).
  Future<GpuAttestationResult?> localCheck(String model) async {
    return verifier?.verifyLocal(model: model);
  }

  /// Runs before a request; returns the error that blocks it, or `null`.
  Future<AttestationFailedException?> before(String model) async {
    final v = verifier;
    if (v == null || mode == GpuCheckMode.off) return null;
    if (_skipOnce) {
      _skipOnce = false;
      return null;
    }
    final missing = _noEvidence[model];
    if (missing != null && mode == GpuCheckMode.after) return null;
    final result = missing ?? await _ensure(v, model);
    if (result == null || result.ok) return null;
    // After: a model without evidence only gets a hint, nothing to block.
    if (result.category == GpuReason.noEvidence && mode == GpuCheckMode.after) {
      return null;
    }
    return AttestationFailedException(
      'GPU-Prüfung nicht bestanden (${result.detail ?? result.verdict.name}'
      '${result.category == null ? '' : ' [${result.category}]'}); '
      'Anfrage nicht gesendet',
      stage: 'gpu',
      category: result.category,
      unavailable:
          result.verdict == GpuVerdict.unreachable ||
          result.verdict == GpuVerdict.timeout,
    );
  }

  /// Warm-up: does the check [before] would do, without consuming
  /// [allowOnce] and without a result (a failure is remembered and reported
  /// like on a request, the request itself then fails the same way).
  Future<void> warm(String model) async {
    final v = verifier;
    if (v == null || mode == GpuCheckMode.off) return;
    await _ensure(v, model);
  }

  /// The check [mode] demands for [model] now (shared by concurrent callers
  /// of the same kind); `null` if nothing is due.
  Future<GpuAttestationResult>? _ensure(
    GpuAttestationVerifier v,
    String model,
  ) {
    final full = switch (mode) {
      GpuCheckMode.before => _ok[model] != true,
      GpuCheckMode.after => _needsCheck.contains(model),
      GpuCheckMode.off => false,
    };
    if (!full && _localOk.contains(model)) return null;
    if (_noEvidence.containsKey(model)) return null;
    final key = '${full ? 'full' : 'local'}:$model';
    return _inflight[key] ??= (full ? _check(v, model) : _checkLocal(v, model))
        .whenComplete(() {
          unawaited(_inflight.remove(key)); // not awaited: it is this future
        });
  }

  /// Runs after a verified answer (mode `after`), without waiting.
  void after(String model) {
    final v = verifier;
    if (mode != GpuCheckMode.after ||
        v == null ||
        _ok[model] == true ||
        _noEvidence.containsKey(model)) {
      return;
    }
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
              GpuReason.timeout,
            ),
          );
    } on Object {
      result = const GpuAttestationResult(
        GpuVerdict.unreachable,
        'interner Fehler',
      );
    }
    _ok[model] = result.ok;
    if (result.category == GpuReason.noEvidence) {
      _noEvidence[model] = result;
    } else if (result.ok) {
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
              GpuReason.timeout,
            ),
          );
    } on Object {
      result = const GpuAttestationResult(
        GpuVerdict.unreachable,
        'interner Fehler',
      );
    }
    if (result.ok) _localOk.add(model);
    if (result.category == GpuReason.noEvidence) _noEvidence[model] = result;
    onResult(model, result, false);
    return result;
  }
}
