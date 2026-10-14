import 'dart:async';

import 'package:wendelin_core/wendelin_core.dart';

import '../common/exchange_tap.dart';
import '../common/health_probe.dart';
import '../common/http_settings.dart';
import '../openai/openai_adapter.dart';
import 'attestation_log.dart';
import 'attestation_policy.dart';
import 'attestation_types.dart';
import 'gpu_attestation.dart';

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
    this.gpuVerifier,
    this.gpuMode = GpuCheckMode.off,
    this.policy = const AttestationPolicy(),
    this.logSink,
    this.settings = const HttpSettings(),
    this.retryDelay = const Duration(seconds: 2),
    this.gpuTimeout = const Duration(seconds: 15),
  });

  /// The wrapped adapter. It must send `provider.aci_verified: true`
  /// (`OpenAiOptions.extraBody`) so the gateway enforces the upstream check.
  final OpenAiChatAdapter inner;

  /// Attestation and receipt verification.
  final AttestationVerifier verifier;

  /// Provider profile id (audit log, pin).
  final String profileId;

  /// NRAS check; `null` = unavailable.
  final GpuAttestationVerifier? gpuVerifier;

  /// When the GPU evidence is checked (changeable at runtime).
  GpuCheckMode gpuMode;

  /// Stage results → status.
  final AttestationPolicy policy;

  /// Receives the audit-log entries.
  final AttestationLogSink? logSink;

  /// Clock and diagnostic log.
  final HttpSettings settings;

  /// Wait between receipt attempts.
  final Duration retryDelay;

  /// Upper bound for one GPU check.
  final Duration gpuTimeout;

  AttestedSession? _session;
  AttestationFailedException? _lock;
  Future<AttestationFailedException?>? _attesting;
  Future<AttestationReport?>? _pending;
  final Map<String, bool> _gpuOk = {};
  bool _gpuNeedsCheck = false;
  bool _skipGpuOnce = false;
  int _counter = 0;
  final StreamController<AttestationReport> _reports =
      StreamController<AttestationReport>.broadcast();

  @override
  Stream<AttestationReport> get reports => _reports.stream;

  @override
  Future<AttestationReport?> pendingReport() async => _pending;

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
      logId: _lastLogId,
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
  void allowNextRequestWithoutGpuCheck() => _skipGpuOnce = true;

  @override
  Stream<ChatEvent> chat(ChatRequest req, {CancelToken? cancel}) async* {
    _pending = null;
    final error = await _prepare(req.model);
    if (error != null) {
      _log('Wendelin/attest: Anfrage nicht gesendet (${error.stage})');
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
        _pending = _checkReceipt(record!, session, req.model);
      } else if (event is ErrorEvent) {
        _pending = Future.value();
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
    return _gpuBefore(model);
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
    final id = _record(
      AttestationLogKind.session,
      result.status,
      result.stages,
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
      _gpuOk.clear();
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
      var stages = <StageResult>[];
      var status = AttestationStatus.red;
      var pinChanged = false;
      if (id == null || id.isEmpty) {
        stages = const [
          StageResult.fail(
            AttestationStage.receiptFetch,
            'Antwort ohne x-receipt-id',
          ),
        ];
      } else {
        for (var attempt = 1; ; attempt++) {
          final result = await verifier.verifyReceipt(
            ReceiptRef(id: id, session: session),
            record.requestBytes,
            record.responseBytes,
          );
          stages = result.stages;
          pinChanged = result.pinChanged;
          status = policy.receiptStatus(stages, attempt: attempt);
          if (status != AttestationStatus.yellow) break;
          _emit(
            AttestationReport(
              logId: _record(
                AttestationLogKind.receipt,
                status,
                stages,
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
      final logId = _record(
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
      final report = AttestationReport(
        logId: logId,
        status: status,
        detail: pinChanged
            ? 'Anbieter hat ein Update ausgerollt, neu geprüft'
            : policy.notes(stages).firstOrNull,
      );
      _emit(report);
      if (status == AttestationStatus.green) _gpuAfter(model);
      return report;
    } on Object {
      _lock = const AttestationFailedException(
        'Antwort nicht verifiziert (internal)',
        stage: 'internal',
      );
      final report = AttestationReport(
        logId: _record(
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

  // --- GPU --------------------------------------------------------------

  Future<AttestationFailedException?> _gpuBefore(String model) async {
    final verifier = gpuVerifier;
    if (gpuMode == GpuCheckMode.off || verifier == null) return null;
    if (_skipGpuOnce) {
      _skipGpuOnce = false;
      return null;
    }
    final needed = gpuMode == GpuCheckMode.before
        ? _gpuOk[model] != true
        : _gpuNeedsCheck;
    if (!needed) return null;
    final result = await _gpuCheck(verifier, model);
    if (result.ok) return null;
    final unavailable =
        result.verdict == GpuVerdict.unreachable ||
        result.verdict == GpuVerdict.timeout;
    return AttestationFailedException(
      'GPU-Prüfung nicht bestanden (${result.detail ?? result.verdict.name}); '
      'Anfrage nicht gesendet',
      stage: 'gpu',
      unavailable: unavailable,
    );
  }

  void _gpuAfter(String model) {
    final verifier = gpuVerifier;
    if (gpuMode != GpuCheckMode.after ||
        verifier == null ||
        _gpuOk[model] == true) {
      return;
    }
    unawaited(_gpuCheck(verifier, model));
  }

  Future<GpuAttestationResult> _gpuCheck(
    GpuAttestationVerifier verifier,
    String model,
  ) async {
    final GpuAttestationResult result;
    try {
      result = await verifier
          .verify(model: model)
          .timeout(
            gpuTimeout,
            onTimeout: () => const GpuAttestationResult(
              GpuVerdict.timeout,
              'Zeitüberschreitung',
            ),
          );
    } on Object {
      return _gpuResult(
        model,
        const GpuAttestationResult(GpuVerdict.unreachable, 'interner Fehler'),
      );
    }
    return _gpuResult(model, result);
  }

  GpuAttestationResult _gpuResult(String model, GpuAttestationResult result) {
    _gpuOk[model] = result.ok;
    _gpuNeedsCheck = !result.ok;
    final status = result.ok ? AttestationStatus.green : AttestationStatus.red;
    final id = _record(AttestationLogKind.gpu, status, [
      StageResult(
        AttestationStage.quote,
        result.ok ? StageOutcome.pass : StageOutcome.fail,
        'gpu: ${result.verdict.name}',
      ),
    ], model: model);
    _emit(
      AttestationReport(
        logId: id,
        status: status,
        detail: result.ok
            ? null
            : 'GPU-Prüfung: ${result.detail ?? result.verdict.name}',
      ),
    );
    return result;
  }

  // --- Log --------------------------------------------------------------

  String _lastLogId = '';

  String _record(
    AttestationLogKind kind,
    AttestationStatus status,
    List<StageResult> stages, {
    String? model,
    String? receiptId,
    AttestedSession? session,
    List<String> notes = const [],
  }) {
    final now = settings.clock.now();
    final id = 'att-${now.microsecondsSinceEpoch}-${_counter++}';
    _lastLogId = id;
    for (final s in stages) {
      _log('Wendelin/attest: ${kind.name} ${s.stage.id}=${s.outcome.name}');
    }
    _log('Wendelin/attest: ${kind.name} ${status.name}');
    logSink?.record(
      AttestationLogEntry(
        logId: id,
        time: now,
        kind: kind,
        profileId: profileId,
        status: status,
        stages: stages,
        model: model,
        receiptId: receiptId,
        repoCommit: session?.repoCommit,
        composeHash: session?.composeHash,
        keysetDigest: session?.keysetDigest,
        notes: notes,
      ),
    );
    return id;
  }

  void _emit(AttestationReport report) {
    if (!_reports.isClosed) _reports.add(report);
  }

  void _log(String line) => settings.log?.call(line);

  @override
  String toString() => 'AttestedProvider($profileId, $inner)';
}
