import 'dart:async';

import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

/// Reports a failed audit write (default: the zone's error handler).
typedef AuditErrorHandler = void Function(Object error, StackTrace stack);

/// Writes the audit log (concept: „Logging“): requests, routing, tool calls
/// (as [ToolAuditSink] of the tool executor), confirmations, escalations,
/// usage, verification results and failures.
///
/// Writes are queued in order and never block the caller. [flush] waits
/// for all pending writes. A failing write is reported to [onError], never
/// swallowed. Payloads hold no secrets; the repository additionally
/// redacts secret-looking fields.
final class AuditRecorder implements ToolAuditSink {
  /// Creates the recorder.
  AuditRecorder(this.repository, {required this.clock, this.onError});

  /// Audit log.
  final AuditLogRepository repository;

  /// Time of the entries.
  final Clock clock;

  /// Receives write failures; `null` = current zone.
  final AuditErrorHandler? onError;

  Future<void> _tail = Future.value();

  /// Waits until every entry recorded so far is written.
  Future<void> flush() => _tail;

  /// A user request was sent; [trigger] is what started it (`pushToTalk`,
  /// `assistant`, …; `null` = typed in the app).
  void request(String sessionId, UserInput input, {String? trigger}) =>
      _write(AuditKind.request, sessionId, {
        'source': input.source.name,
        'trigger': ?trigger,
        'text': input.text,
        'language': ?input.language,
        'sttConfidence': ?input.sttConfidence,
        if (input.requestEscalation) 'requestEscalation': true,
      });

  /// The user answered a tool confirmation.
  void toolConfirmation(
    String sessionId,
    ConfirmationRequired event, {
    required bool approved,
  }) => _write(AuditKind.confirmation, sessionId, {
    'type': 'tool',
    'callId': event.call.id,
    'tool': event.call.name,
    'description': event.description,
    'approved': approved,
  });

  /// The user answered an escalation below the privacy level.
  void escalationConfirmation(
    String sessionId,
    EscalationConfirmationRequired event, {
    required bool approved,
  }) => _write(AuditKind.confirmation, sessionId, {
    'type': 'escalation',
    'fromProfile': event.fromProfile,
    'toProfile': event.toProfile,
    'reason': event.reason.name,
    'approved': approved,
  });

  /// Records what [event] means for the audit log (no-op for streaming
  /// events and events recorded elsewhere).
  void agentEvent(String sessionId, AgentEvent event) {
    switch (event) {
      case Routed(:final profileId, :final modelId, :final reason):
        _write(AuditKind.routing, sessionId, {
          'profileId': profileId,
          'modelId': modelId,
          'reason': reason,
        });
      case Escalated(:final fromProfile, :final toProfile, :final reason):
        _write(AuditKind.escalation, sessionId, {
          'fromProfile': fromProfile,
          'toProfile': toProfile,
          'reason': reason.name,
        });
      case UsageReported(
        :final profileId,
        :final modelId,
        :final usage,
        :final costMicros,
      ):
        _write(AuditKind.usage, sessionId, {
          'profileId': profileId,
          'modelId': modelId,
          'inputTokens': usage.inputTokens,
          'outputTokens': usage.outputTokens,
          'cacheReadTokens': usage.cachedInputTokens,
          'cacheWriteTokens': usage.cacheWriteTokens,
          'costMicros': costMicros,
        });
      case Verification(:final profileId, :final status, :final detail):
        _write(AuditKind.verification, sessionId, {
          'profileId': profileId,
          'status': status.name,
          'detail': ?detail,
        });
      case BudgetWarning(
        :final profileId,
        :final spentMicros,
        :final budgetMicros,
      ):
        _write(AuditKind.usage, sessionId, {
          'budgetWarning': true,
          'profileId': profileId,
          'spentMicros': spentMicros,
          'budgetMicros': budgetMicros,
        });
      case AgentFailed(:final error, :final message):
        _write(AuditKind.error, sessionId, {
          'error': error.name,
          'message': message,
        });
      case AgentTextDelta() ||
          AgentTextReset() ||
          AgentThinkingDelta() ||
          ToolCallStarted() ||
          ConfirmationRequired() ||
          EscalationConfirmationRequired() ||
          ToolCallFinished() ||
          AgentDone():
      // Tool calls come from the executor (record), answers to
      // confirmations from the controller; text is not logged here.
    }
  }

  @override
  void record(ToolAuditEntry entry) =>
      _write(AuditKind.toolCall, entry.sessionId, {
        'callId': entry.callId,
        'tool': entry.tool,
        'arguments': entry.argumentsJson,
        'decision': entry.decision.name,
        'status': entry.status.name,
        'durationMs': entry.duration.inMilliseconds,
      });

  void _write(AuditKind kind, String? sessionId, Map<String, Object?> data) {
    final entry = AuditEntry(
      at: clock.now(),
      kind: kind,
      sessionId: sessionId,
      payload: data,
    );
    _tail = _tail.then((_) async {
      try {
        await repository.record(entry);
      } on Object catch (e, s) {
        (onError ?? Zone.current.handleUncaughtError)(e, s);
      }
    });
  }
}
