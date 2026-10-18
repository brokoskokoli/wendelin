import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';

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
import 'near/near_verifier.dart';
import 'session_channel.dart';
import 'tls_pin_gate.dart';

/// Decorator that makes an OpenAI-compatible TEE provider verifiable
/// (concept: „TEE-Provider und Attestierung“, ADR 0014).
///
/// - Before the first request, after `not_after` and after a pin change the
///   provider is attested. If that fails, **no request is sent**; the call
///   ends with `ErrorEvent(AttestationFailedException)` and the provider is
///   locked until [reattest] succeeds. The request never goes to another
///   provider because of it.
/// - Every request is end-to-end encrypted to the E2EE key of the attested
///   keyset (WP62, [PhalaE2eeChannel]); a missing key, a response without
///   the E2EE headers, plaintext in encrypted fields or a decryption error
///   ends the call with `ErrorEvent(AttestationFailedException)` (stage
///   `e2ee.*`), never with plaintext and never at another provider; the next
///   call attests again.
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
    Future<void> Function(Duration) sleep = _sleep,
    this.tlsPin,
    bool requireUpstreamEnforced = true,
    Duration gpuTimeout = const Duration(seconds: 15),
    String? sessionScope,
    this.connectionIdle = const Duration(minutes: 4),
  }) : sessionScope = sessionScope ?? inner.baseUrl.toString(),
       _sleepFn = sleep {
    final provider = inner.options.extraBody['provider'];
    if (requireUpstreamEnforced &&
        (provider is! Map || provider['aci_verified'] != true)) {
      throw ArgumentError.value(
        inner.options.extraBody,
        'inner',
        'OpenAiOptions.extraBody must contain provider.aci_verified: true '
            '(the gateway must enforce the upstream check)',
      );
    }
    final channel = inner.wireCodec;
    if (channel is! SessionBoundChannel || channel.bound) {
      throw ArgumentError.value(
        channel,
        'inner',
        'The adapter needs an unbound SessionBoundChannel as wireCodec '
            '(every request to the gateway must be end-to-end encrypted)',
      );
    }
    channel.bind(() => _session, settings.clock);
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

  /// What a session of this provider is valid for (gateway URL, for NEAR
  /// also the model). A rebuilt provider takes over the verified session of
  /// its predecessor only for the same scope ([adoptSessionOf]).
  final String sessionScope;

  /// How long the pre-opened connection counts as alive (below the idle
  /// timeout of the pinned client).
  final Duration connectionIdle;
  DateTime? _connectedAt;
  String _nextReason = 'no-session';

  /// When the GPU evidence is checked (changeable at runtime).
  GpuCheckMode get gpuMode => _gpu.mode;
  set gpuMode(GpuCheckMode mode) => _gpu.mode = mode;

  /// Stage results → status.
  final AttestationPolicy policy;

  /// Receives the audit-log entries.
  final AttestationLogSink? logSink;

  /// Clock and diagnostic log.
  final HttpSettings settings;

  /// Base wait between receipt attempts (grows to three times this).
  final Duration retryDelay;

  /// Waits between receipt attempts (replaceable in tests).
  final Future<void> Function(Duration) _sleepFn;

  static Future<void> _sleep(Duration d) => Future<void>.delayed(d);

  /// Pin state of the enforcing client of [inner] (WP61). If a connection
  /// is refused because its certificate does not match the attestation, the
  /// provider attests once more (certificate rotation) and retries the
  /// request; a second mismatch locks the provider.
  final TlsPinGate? tlsPin;

  AttestedSession? _session;
  List<StageResult> _lastStages = const [];
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

  /// Whether tool definitions, calls and results are end-to-end encrypted
  /// too (NEAR AI). The UI then shows no „tools only via TLS“ hint.
  bool get toolsEncrypted {
    final channel = inner.wireCodec;
    return channel is SessionBoundChannel && channel.encryptsTools;
  }

  /// The provider refuses requests until [reattest] succeeds.
  bool get locked => _lock != null;

  /// Result per stage of the latest session attestation (setup dialog:
  /// „Ergebnis je Stufe“); empty before the first one.
  List<StageResult> get lastSessionStages => _lastStages;

  /// The attested session, if there is a valid one.
  AttestedSession? get session => _session;

  @override
  ProviderType get type => inner.type;

  @override
  ProviderCapabilities get caps => inner.caps;

  @override
  Future<List<ModelInfo>> listModels() async {
    if (await _prepareSession() case final error?) throw error;
    return inner.listModels();
  }

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
    final error = await _attest('reattest');
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

  /// Prepares the first request in the background (app start, overlay
  /// start): attests (unless the session is valid), fetches the GPU
  /// evidence of the default model **in parallel** (modes `before`/`after`)
  /// and opens the pinned connection, so the first request waits for none
  /// of it. Does nothing if the provider is locked. A failed attestation
  /// locks it like on a request and is reported through [reports]. Never
  /// weakens a check: everything that blocks a request still blocks it.
  Future<void> warmUp({String? model}) async {
    if (_lock != null) return;
    final session = _session;
    final valid =
        session != null && settings.clock.now().isBefore(session.notAfter);
    // Attestation first: it resets the GPU results of the old session.
    final attesting = valid ? null : _attest();
    final gpu = _gpu.warm(model ?? inner.defaultModel);
    final error = await attesting;
    await gpu;
    if (error == null && _lock == null && _session != null) {
      await _preconnect();
    }
  }

  /// Opens the pinned connection to the gateway ahead of the first request
  /// (TLS handshake and pin check; a light `GET /models`). The result is
  /// ignored: a refused connection fails the real request the same way.
  Future<void> _preconnect() async {
    final at = _connectedAt;
    final now = settings.clock.now();
    if (at != null && now.difference(at) < connectionIdle) return;
    _connectedAt = now;
    try {
      await inner.listModels().timeout(const Duration(seconds: 10));
    } on Object {
      _connectedAt = null;
    }
  }

  /// Takes over the verified session of [previous], the provider this one
  /// replaces (profile rebuilt, nothing changed): the session, its pin for
  /// the enforcing client and the GPU results. Only for the same
  /// [sessionScope], only while the session is valid, neither provider is
  /// locked and the pin of [previous] is still set (not while it re-attests).
  /// Returns whether it was taken. Nothing is verified less: the session is
  /// exactly one this process verified completely; it ends at the same
  /// `not_after` as there.
  bool adoptSessionOf(AttestedProvider previous, {String? reason}) {
    final taken = previous._session;
    final pin = previous.tlsPin?.expected;
    final gate = tlsPin;
    if (identical(previous, this) ||
        _session != null ||
        _lock != null ||
        previous._lock != null ||
        previous.sessionScope != sessionScope ||
        taken == null ||
        (previous.tlsPin == null) != (gate == null) ||
        (gate != null && pin == null) ||
        !settings.clock.now().isBefore(taken.notAfter)) {
      return false;
    }
    if (gate != null) gate.expect(pin);
    _session = taken;
    _lastStages = previous._lastStages;
    _gpu.adopt(previous._gpu);
    final mine = verifier;
    final theirs = previous.verifier;
    if (mine is NearVerifier && theirs is NearVerifier) {
      mine.adoptGpuEvidence(theirs);
    }
    _audit.log(
      'Wendelin/attest: Sitzung übernommen (Profil neu aufgebaut'
      '${reason == null ? '' : ': $reason'})',
    );
    return true;
  }

  /// Lets the next request through although the GPU check failed or was not
  /// reachable (the user chose „ohne GPU-Prüfung senden“). Valid once.
  void allowNextRequestWithoutGpuCheck() => _gpu.allowOnce();

  /// Whether the provider delivers GPU evidence for [model] (`false`: no
  /// evidence, so no GPU check is possible); `null` if unknown.
  Future<bool?> hasGpuEvidence(String model) => _gpu.hasEvidence(model);

  /// Local GPU evidence check for [model] (setup); `null` without verifier.
  /// Unlike [hasGpuEvidence] it also tells a real failure.
  Future<GpuAttestationResult?> checkGpuEvidence(String model) =>
      _gpu.localCheck(model);

  @override
  Stream<ChatEvent> chat(ChatRequest req, {CancelToken? cancel}) async* {
    _latest = null;
    for (var attempt = 0; ; attempt++) {
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
      var toolsInvolved = req.tools.isNotEmpty || _hasToolTraffic(req);
      ExchangeRecord? record;
      var rotated = false;
      await for (final event in inner.chatObserved(
        req,
        cancel: cancel,
        observer: (r) => record = r,
      )) {
        if (event is ErrorEvent && _isTlsMismatch(event.error)) {
          // The connection was refused before any byte of the request.
          if (attempt == 0) {
            _audit.log('Wendelin/attest: TLS-Schlüssel weicht ab, neu prüfen');
            _session = null;
            _nextReason = 'tls-mismatch';
            rotated = true;
            break;
          }
          final failure = event.error;
          if (failure is AttestationFailedException) _lock = failure;
        }
        if (event is ToolCallComplete || event is ToolCallDelta) {
          toolsInvolved = true;
        }
        if (event is Done && record != null) {
          final involved = toolsInvolved && !toolsEncrypted;
          _latest = _byRequest[req] = _checkReceipt(
            record!,
            session,
            req.model,
            toolsInvolved: involved,
          );
        } else if (event is ErrorEvent) {
          _latest = _byRequest[req] = Future.value();
          if (_isE2eeFailure(event.error)) {
            // Keys may have rotated: attest again before the next request.
            _audit.log('Wendelin/attest: E2EE-Fehler (${_stageOf(event)})');
            _recordE2eeFailure(event.error as AttestationFailedException, req);
            _session = null;
            _nextReason = 'e2ee-failure';
          }
        }
        yield event;
      }
      if (!rotated) return;
    }
  }

  /// Writes a log entry with the failed E2EE stage (visible in the log).
  void _recordE2eeFailure(AttestationFailedException e, ChatRequest req) {
    final stage = AttestationStage.values
        .where((s) => s.id == e.stage)
        .firstOrNull;
    _emit(
      AttestationReport(
        logId: _audit.record(
          AttestationLogKind.receipt,
          AttestationStatus.red,
          [StageResult.fail(stage ?? AttestationStage.e2eeRequest, e.message)],
          model: req.model,
          session: _session,
        ),
        status: AttestationStatus.red,
        detail: e.message,
      ),
    );
  }

  static bool _hasToolTraffic(ChatRequest r) => r.messages.any(
    (m) =>
        m.role == Role.tool ||
        m.content.any((b) => b is ToolCallBlock || b is ToolResultBlock),
  );

  static bool _isE2eeFailure(Object? error) =>
      error is AttestationFailedException && error.stage.startsWith('e2ee.');

  static String _stageOf(ErrorEvent event) {
    final error = event.error;
    return error is AttestationFailedException ? error.stage : 'e2ee';
  }

  static bool _isTlsMismatch(Object? error) =>
      error is AttestationFailedException &&
      error.stage == AttestationStage.tlsSpki.id;

  // --- Session ----------------------------------------------------------

  /// Session and GPU check run in parallel (the evidence does not depend on
  /// the session); the request waits for both. The session error wins and
  /// does not wait for the GPU check.
  Future<AttestationFailedException?> _prepare(String model) async {
    // The attestation starts first: it resets the GPU results of the old
    // session before the GPU check looks at them.
    final session = _prepareSession();
    final gpu = _gpu.before(model);
    if (await session case final error?) return error;
    return gpu;
  }

  Future<AttestationFailedException?> _prepareSession() async {
    if (_lock != null) return _lock;
    final session = _session;
    if (session == null || !settings.clock.now().isBefore(session.notAfter)) {
      final why = session == null ? _nextReason : 'expired';
      _nextReason = 'no-session';
      return _attest(why);
    }
    return null;
  }

  Future<AttestationFailedException?> _attest([String reason = 'requested']) =>
      _attesting ??= _doAttest(reason).whenComplete(() => _attesting = null);

  Future<AttestationFailedException?> _doAttest(String reason) async {
    // Why this check runs at all (the log showed 5 checks in 4 minutes).
    _audit.log('Wendelin/attest: Sitzungsprüfung startet (Grund=$reason)');
    _connectedAt = null;
    _gpu.reset();
    final AttestationResult result;
    try {
      result = await verifier.attest();
    } on Object {
      return _lock = const AttestationFailedException(
        'TEE-Anbieter nicht verifiziert: interner Fehler',
        stage: 'internal',
      );
    }
    _lastStages = List.unmodifiable(result.stages);
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
    String model, {
    bool toolsInvolved = false,
  }) async {
    try {
      final Object v = verifier;
      final id =
          record.responseHeaders['x-receipt-id'] ??
          (v is ReceiptIdSource ? v.receiptIdOf(record) : null);
      final (:stages, :status, :pinChanged) = id == null || id.isEmpty
          ? (
              stages: const [
                StageResult(
                  AttestationStage.receiptFetch,
                  StageOutcome.unavailable,
                  'Antwort ohne x-receipt-id',
                  StageResult.receiptMissing,
                ),
              ],
              status: AttestationStatus.unconfirmed,
              pinChanged: false,
            )
          : await _receiptAttempts(id, record, session, model, toolsInvolved);
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
          _nextReason = 'keyset-changed';
        } else {
          _lock = AttestationFailedException(
            'Antwort nicht verifiziert (${_problem(stages)}); '
            'Anbieter gesperrt bis zur neuen Prüfung',
            stage: _problem(stages),
          );
        }
      }
      final problem = status != AttestationStatus.green
          ? stages.where((s) => s.code != null).firstOrNull
          : null;
      final report = AttestationReport(
        logId: logId,
        status: status,
        detail: pinChanged
            ? 'Anbieter hat ein Update ausgerollt, neu geprüft'
            : problem?.detail ?? policy.notes(stages).firstOrNull,
        reasonCode: problem?.code,
        toolsInvolved: toolsInvolved,
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
        toolsInvolved: toolsInvolved,
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
    bool toolsInvolved,
  ) async {
    for (var attempt = 1; ; attempt++) {
      final result = await verifier.verifyReceipt(
        ReceiptRef(
          id: id,
          session: session,
          alternateId: chatIdOf(record.responseBytes),
        ),
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
          toolsInvolved: toolsInvolved,
        ),
      );
      // 2 s, 4 s, 6 s, 6 s, 6 s: about 24 s in all for a receipt the
      // gateway has not written yet.
      await _sleepFn(retryDelay * min(attempt, 3));
    }
  }

  /// The first `"id":"…"` of a response (plain JSON or the first SSE chunk),
  /// the chat id; `null` if there is none or it is odd.
  @visibleForTesting
  static String? chatIdOf(Uint8List response) {
    final head = utf8.decode(
      response.length > 4096 ? response.sublist(0, 4096) : response,
      allowMalformed: true,
    );
    final id = RegExp(r'"id"\s*:\s*"([A-Za-z0-9_.:-]{1,128})"')
        .firstMatch(head)
        ?.group(1);
    // Not a path segment like `.` or `..`, and not only punctuation.
    if (id == null || !id.contains(RegExp(r'[A-Za-z0-9]'))) return null;
    return id;
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
    final unavailable =
        result.verdict == GpuVerdict.unreachable ||
        result.verdict == GpuVerdict.timeout;
    final code = result.ok
        ? null
        : unavailable
        ? 'gpu_unavailable'
        : 'gpu_failed';
    // Verdict, source and category only (HTTP status, timeout, no evidence,
    // …), no content. `via` tells whether NVIDIA's signed answer or only the
    // local nonce binding was checked.
    final via = nras ? 'nras' : 'local';
    _audit.log(
      result.ok
          ? 'Wendelin/attest: gpu gpu=pass via=$via'
          : 'Wendelin/attest: gpu gpu=fail '
                'reason=${result.category ?? 'unknown'} via=$via',
    );
    if (result.category == GpuReason.noEvidence &&
        _gpu.mode != GpuCheckMode.before) {
      // Mode „Nachher“: only a hint, the request is not blocked and the
      // answer is not marked (the provider just has no evidence).
      _audit.record(AttestationLogKind.gpu, AttestationStatus.yellow, [
        const StageResult(
          AttestationStage.gpuEvidence,
          StageOutcome.info,
          'GPU: kein Nachweis des Anbieters, nicht prüfbar',
        ),
      ], model: model);
      return;
    }
    final id = _audit.record(AttestationLogKind.gpu, status, [
      StageResult(
        AttestationStage.gpu,
        result.ok ? StageOutcome.pass : StageOutcome.fail,
        result.ok
            ? (nras
                  ? 'geprüft (NRAS, Signatur '
                        '${result.signatureChecked ? '' : 'un'}geprüft)'
                  : 'Nonce-Bindung lokal geprüft, nicht über NVIDIA geprüft')
            : 'gpu: ${result.detail ?? result.verdict.name}',
        code,
      ),
    ], model: model);
    if (result.ok && !nras) return; // routine local check: no report
    _emit(
      AttestationReport(
        logId: id,
        status: status,
        detail: result.ok
            ? null
            : 'GPU-Prüfung: ${result.detail ?? result.verdict.name}',
        reasonCode: code,
      ),
    );
  }

  void _emit(AttestationReport report) {
    if (!_reports.isClosed) _reports.add(report);
  }

  @override
  String toString() => 'AttestedProvider($profileId, $inner)';
}
