import 'dart:async';

import 'package:wendelin_core/wendelin_core.dart';

import '../common/exchange_tap.dart';
import '../common/health_probe.dart';
import '../common/http_settings.dart';
import '../openai/openai_adapter.dart';
import 'attestation_audit.dart';
import 'attestation_log.dart';
import 'attestation_policy.dart';
import 'attestation_types.dart';
import 'gpu_attestation.dart';
import 'gpu_gate.dart';

/// Decorator that makes an OpenAI-compatible TEE provider verifiable
/// (concept: „TEE-Provider und Attestierung“, ADR 0014).
///
/// - Before the first request, after `not_after` and after a pin change the
///   provider is attested. If that fails, **no request is sent**; the call
///   ends with `ErrorEvent(AttestationFailedException)` and the provider is
///   locked until [reattest] succeeds. (A fallback to another provider is
///   the agent's escalation with user confirmation.)
/// - After the stream ended it fetches the receipt, checks it against the
///   exact bytes of the exchange (up to 3 attempts for a network error) and
///   reports the result through [pendingReport] and [reports]. A red receipt
///   locks the provider.
/// - The GPU check ([gpuMode]) runs before (fail-closed) or after the
///   request; the result is cached for the session.
///
/// Logs only stage ids and outcomes (`Wendelin/attest:`), never prompt,
/// answer or receipt content.
final class AttestedProvider implements LlmProvider, AttestationAware {
  /// Creates the decorator around [inner].
  AttestedProvider({
    required this.inner,
    required this.verifier,
    required this.profileId,
    GpuAttestationVerifier? gpuVerifier,
    GpuCheckMode gpuMode = GpuCheckMode.off,
    this.policy = const AttestationPolicy(),
    this.logSink,
    this.settings = const HttpSettings(),
    this.retryDelay = const Duration(seconds: 2),
    Duration gpuTimeout = const Duration(seconds: 15),
  }) {
    final provider = inner.options.extraBody['provider'];
    if (provider is! Map || provider['aci_verified'] != true) {
      throw ArgumentError.value(
        inner.options.extraBody,
        'inner',
        'OpenAiOptions.extraBody must contain provider.aci_verified: true '
            '(the gateway must enforce the upstream check)',
      );
    }
    _gpu = GpuGate(
      mode: gpuMode,
      verifier: gpuVerifier,
      timeout: gpuTimeout,
      onResult: _onGpuResult,
    );
  }

  /// The wrapped adapter. It must send `provider.aci_verified: true`
  /// (`OpenAiOptions.extraBody`) so the gateway enforces the upstream check.
  final OpenAiChatAdapter inner;

  /// Attestation and receipt verification.
  final AttestationVerifier verifier;

  /// Provider profile id (audit log, pin).
  final String profileId;

  late final GpuGate _gpu;

  /// When the GPU evidence is checked (changeable at runtime).
  GpuCheckMode get gpuMode => _gpu.mode;
  set gpuMode(GpuCheckMode mode) => _gpu.mode = mode;

  /// Stage results → status.
  final AttestationPolicy policy;

  /// Receives the audit-log entries.
  final AttestationLogSink? logSink;

  /// Clock and diagnostic log.
  final HttpSettings settings;

  /// Wait between receipt attempts.
  final Duration retryDelay;

  AttestedSession? _session;
  AttestationFailedException? _lock;
  Future<AttestationFailedException?>? _attesting;
  Future<AttestationReport?>? _latest;
  final Expando<Future<AttestationReport?>> _byRequest =
      Expando<Future<AttestationReport?>>('receipt report per chat call');
  late final AttestationAudit _audit = AttestationAudit(
    profileId,
    logSink,
    settings,
  );
  final StreamController<AttestationReport> _reports =
      StreamController<AttestationReport>.broadcast();

  /// Every result of the provider as it becomes final: session attestation,
  /// receipt checks (also interim yellow ones) and GPU checks. A **failed
  /// GPU check** (also the asynchronous one of mode `after`) arrives here as
  /// a red report with `reasonCode` `gpu_failed` (evidence rejected or nonce
  /// not bound) or `gpu_unavailable` (NRAS not reachable, timeout), and
  /// `detail` „GPU-Prüfung: …“; WP52 subscribes to show the warning.
  @override
  Stream<AttestationReport> get reports => _reports.stream;

  @override
  Future<AttestationReport?> reportFor(ChatRequest request) =>
      _byRequest[request] ?? Future.value();

  /// Report of the most recently started `chat` call (convenience for tests
  /// and single-run callers; the agent uses [reportFor]).
  Future<AttestationReport?> pendingReport() async => _latest;

  /// The provider refuses requests until [reattest] succeeds.
  bool get locked => _lock != null;

  /// The attested session, if there is a valid one.
  AttestedSession? get session => _session;

  @override
  ProviderType get type => inner.type;

  @override
  ProviderCapabilities get caps => inner.caps;

  @override
  Future<List<ModelInfo>> listModels() => inner.listModels();

  @override
  Future<HealthCheck> test() => runHealthProbe(
    provider: this,
    model: inner.defaultModel,
    clock: settings.clock,
    baseCaps: caps,
  );

  /// Lifts the lock and attests again (user action „neu prüfen“). Returns
  /// the report of the attestation.
  Future<AttestationReport> reattest() async {
    _lock = null;
    _session = null;
    final error = await _attest();
    final stage = error?.stage;
    return AttestationReport(
      logId: _audit.lastLogId,
      status: error == null
          ? AttestationStatus.green
          : error.unavailable
          ? AttestationStatus.yellow
          : AttestationStatus.red,
      detail: stage,
    );
  }

  /// Lets the next request through although the GPU check failed or was not
  /// reachable (the user chose „ohne GPU-Prüfung senden“). Valid once.
  void allowNextRequestWithoutGpuCheck() => _gpu.allowOnce();

  @override
  Stream<ChatEvent> chat(ChatRequest req, {CancelToken? cancel}) async* {
    _latest = null;
    final error = await _prepare(req.model);
    if (error != null) {
      _audit.log('Wendelin/attest: Anfrage nicht gesendet (${error.stage})');
      yield ErrorEvent(error);
      return;
    }
    if (cancel?.isCancelled ?? false) {
      yield const ErrorEvent(CancelledException());
      return;
    }
    final session = _session!;
    ExchangeRecord? record;
    await for (final event in inner.chatObserved(
      req,
      cancel: cancel,
      observer: (r) => record = r,
    )) {
      if (event is Done && record != null) {
        _latest = _byRequest[req] = _checkReceipt(record!, session, req.model);
      } else if (event is ErrorEvent) {
        _latest = _byRequest[req] = Future.value();
      }
      yield event;
    }
  }

  // --- Session ----------------------------------------------------------

  Future<AttestationFailedException?> _prepare(String model) async {
    if (_lock != null) return _lock;
    final session = _session;
    if (session == null || !settings.clock.now().isBefore(session.notAfter)) {
      if (await _attest() case final error?) return error;
    }
    return _gpu.before(model);
  }

  Future<AttestationFailedException?> _attest() =>
      _attesting ??= _doAttest().whenComplete(() => _attesting = null);

  Future<AttestationFailedException?> _doAttest() async {
    final AttestationResult result;
    try {
      result = await verifier.attest();
    } on Object {
      return _lock = const AttestationFailedException(
        'TEE-Anbieter nicht verifiziert: interner Fehler',
        stage: 'internal',
      );
    }
    final session = result.session;
    final green = result.status == AttestationStatus.green && session != null;
    final changed = result.pinChange == PinChange.changed;
    final id = _audit.record(
      AttestationLogKind.session,
      result.status,
      [
        ...result.stages,
        if (_gpu.mode == GpuCheckMode.off)
          const StageResult(
            AttestationStage.gpu,
            StageOutcome.info,
            'GPU: nicht über NVIDIA geprüft',
          ),
      ],
      session: session,
      notes: [
        ...result.notes,
        if (changed) 'Anbieter hat ein Update ausgerollt, neu geprüft',
      ],
    );
    _emit(
      AttestationReport(
        logId: id,
        status: result.status,
        detail: changed
            ? 'Anbieter hat ein Update ausgerollt, neu geprüft'
            : result.notes.firstOrNull,
      ),
    );
    if (green) {
      _session = session;
      _lock = null;
      _gpu.reset();
      return null;
    }
    final problem = result.firstProblem;
    final stage = problem?.stage.id ?? 'attestation';
    if (result.status == AttestationStatus.yellow) {
      return AttestationFailedException(
        'TEE-Anbieter derzeit nicht prüfbar ($stage)',
        stage: stage,
        unavailable: true,
      );
    }
    return _lock = AttestationFailedException(
      'TEE-Anbieter nicht verifiziert ($stage): ${problem?.detail ?? 'Prüfung fehlgeschlagen'}',
      stage: stage,
    );
  }

  // --- Receipt ----------------------------------------------------------

  Future<AttestationReport?> _checkReceipt(
    ExchangeRecord record,
    AttestedSession session,
    String model,
  ) async {
    try {
      final id = record.responseHeaders['x-receipt-id'];
      final (:stages, :status, :pinChanged) = id == null || id.isEmpty
          ? (
              stages: const [
                StageResult.fail(
                  AttestationStage.receiptFetch,
                  'Antwort ohne x-receipt-id',
                ),
              ],
              status: AttestationStatus.red,
              pinChanged: false,
            )
          : await _receiptAttempts(id, record, session, model);
      final logId = _audit.record(
        AttestationLogKind.receipt,
        status,
        stages,
        model: model,
        receiptId: id,
        session: session,
      );
      if (status == AttestationStatus.red) {
        if (pinChanged) {
          _session = null; // new attestation with notice on the next request
        } else {
          _lock = AttestationFailedException(
            'Antwort nicht verifiziert (${_problem(stages)}); '
            'Anbieter gesperrt bis zur neuen Prüfung',
            stage: _problem(stages),
          );
        }
      }
      final problem = status == AttestationStatus.red
          ? stages.where((s) => s.code != null).firstOrNull
          : null;
      final report = AttestationReport(
        logId: logId,
        status: status,
        detail: pinChanged
            ? 'Anbieter hat ein Update ausgerollt, neu geprüft'
            : problem?.detail ?? policy.notes(stages).firstOrNull,
        reasonCode: problem?.code,
      );
      _emit(report);
      if (status == AttestationStatus.green) _gpu.after(model);
      return report;
    } on Object {
      _lock = const AttestationFailedException(
        'Antwort nicht verifiziert (internal)',
        stage: 'internal',
      );
      final report = AttestationReport(
        logId: _audit.record(
          AttestationLogKind.receipt,
          AttestationStatus.red,
          const [
            StageResult.fail(AttestationStage.receiptFetch, 'interner Fehler'),
          ],
          model: model,
        ),
        status: AttestationStatus.red,
      );
      _emit(report);
      return report;
    }
  }

  /// Fetches and checks the receipt; a network failure is retried up to
  /// `policy.maxReceiptAttempts` times with a yellow interim report.
  Future<
    ({List<StageResult> stages, AttestationStatus status, bool pinChanged})
  >
  _receiptAttempts(
    String id,
    ExchangeRecord record,
    AttestedSession session,
    String model,
  ) async {
    for (var attempt = 1; ; attempt++) {
      final result = await verifier.verifyReceipt(
        ReceiptRef(id: id, session: session),
        record.requestBytes,
        record.responseBytes,
      );
      final status = policy.receiptStatus(result.stages, attempt: attempt);
      if (status != AttestationStatus.yellow) {
        return (
          stages: result.stages,
          status: status,
          pinChanged: result.pinChanged,
        );
      }
      _emit(
        AttestationReport(
          logId: _audit.record(
            AttestationLogKind.receipt,
            status,
            result.stages,
            model: model,
            receiptId: id,
          ),
          status: status,
          detail: 'Quittung nicht abrufbar, neuer Versuch',
        ),
      );
      await Future<void>.delayed(retryDelay);
    }
  }

  String _problem(List<StageResult> stages) =>
      stages
          .where(
            (s) =>
                s.outcome == StageOutcome.fail ||
                s.outcome == StageOutcome.unavailable,
          )
          .firstOrNull
          ?.stage
          .id ??
      'receipt';

  void _onGpuResult(String model, GpuAttestationResult result, bool nras) {
    final status = result.ok ? AttestationStatus.green : AttestationStatus.red;
    final id = _audit.record(AttestationLogKind.gpu, status, [
      StageResult(
        AttestationStage.gpu,
        result.ok ? StageOutcome.pass : StageOutcome.fail,
        result.ok
            ? (nras
                  ? 'geprüft (NRAS, Signatur ungeprüft)'
                  : 'Nonce-Bindung lokal geprüft, nicht über NVIDIA geprüft')
            : 'gpu: ${result.verdict.name}',
      ),
    ], model: model);
    if (result.ok && !nras) return; // routine local check: no report
    final unavailable =
        result.verdict == GpuVerdict.unreachable ||
        result.verdict == GpuVerdict.timeout;
    _emit(
      AttestationReport(
        logId: id,
        status: status,
        detail: result.ok
            ? null
            : 'GPU-Prüfung: ${result.detail ?? result.verdict.name}',
        reasonCode: result.ok
            ? null
            : unavailable
            ? 'gpu_unavailable'
            : 'gpu_failed',
      ),
    );
  }

  void _emit(AttestationReport report) {
    if (!_reports.isClosed) _reports.add(report);
  }

  @override
  String toString() => 'AttestedProvider($profileId, $inner)';
}
