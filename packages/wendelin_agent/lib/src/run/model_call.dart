/// One model call of an agent run (concept: „Agent-Schleife“, K8 e): the
/// request as the current target may see it (system prompt with visible
/// memories and the escalation note, catalog, redacted messages), streaming
/// of text and thinking, and the token count. Internal to `wendelin_agent`,
/// not exported.
library;

import 'package:wendelin_core/wendelin_core.dart';

import '../context_builder.dart';
import '../provider_resolver.dart';
import 'privacy_scope.dart';
import 'run_budget.dart';
import 'run_config.dart';
import 'run_state.dart';
import 'spoken_block.dart';

/// Result of one model call.
final class ModelReply {
  /// Creates the reply.
  ModelReply(this.blocks, this.stopReason, this.error);

  /// The answer's blocks; empty on [error].
  final List<ContentBlock> blocks;

  /// Why the model stopped; `null` on [error].
  final StopReason? stopReason;

  /// The provider's error, if any.
  final ProviderException? error;
}

/// Calls the current target's model.
///
/// Invariants:
/// - Before every call the run's floor rises to the taint level
///   ([PrivacyScope.raiseFloorToTaint]), also after an escalation.
/// - The request carries only what the current target may see: its own
///   catalog, the visible memories and the redacted history.
/// - Incomplete tool calls of a failed stream are never executed: the
///   whole reply is discarded on error.
final class ModelCall {
  /// Creates the model calls of [runner]'s run.
  ModelCall(
    this.runner,
    this._state,
    this._privacy,
    this._budget,
    this._control,
  );

  /// The runner (context builder, session, cost estimator).
  final RunConfig runner;
  final RunState _state;
  final PrivacyScope _privacy;
  final RunBudget _budget;
  final RunControl _control;

  /// Calls the model of the current target and streams its answer.
  Future<ModelReply> call() async {
    // Invariant: the floor follows the taint before every model call.
    _privacy.raiseFloorToTaint();
    final config = runner.contextBuilder.config;
    final target = _state.current;
    final catalog = _privacy.catalog;
    final tools = catalog.activeSpecs();
    final request = ChatRequest(
      messages: _privacy.messagesFor(catalog, hasTools: tools.isNotEmpty),
      model: target.modelId,
      maxTokens: config.maxOutputTokens,
      tools: tools,
      temperature: config.temperature,
      systemPrompt: _systemPrompt(),
      metadata: {'sessionId': runner.sessionId},
    );
    final blocks = <ContentBlock>[];
    Usage? usage;
    StopReason? stopReason;
    ProviderException? error;

    final splitter = _state.context.speech == SpeechStyle.twoVersions
        ? SpokenBlockSplitter()
        : null;
    void text(String delta) {
      if (delta.isEmpty) return;
      _control.emit(AgentTextDelta(delta));
      _appendText(blocks, delta);
    }

    void split(SplitText r) {
      if (r.spoken case final spoken?) _control.emit(AgentSpokenText(spoken));
      text(r.text);
    }

    await for (final event in target.provider.chat(
      request,
      cancel: _control.token,
    )) {
      switch (event) {
        case TextDelta(text: final delta):
          if (splitter != null) {
            split(splitter.add(delta));
          } else {
            text(delta);
          }
        case ThinkingDelta(text: final delta):
          if (delta.isNotEmpty) _control.emit(AgentThinkingDelta(delta));
        case ThinkingComplete(:final block):
          blocks.add(block);
        case ProviderBlockComplete(:final block):
          // Kept in place for the same provider; never text, never spoken.
          blocks.add(block);
        case ToolCallDelta():
          break; // assembled calls arrive as ToolCallComplete
        case ToolCallComplete(:final call):
          blocks.add(call);
        case UsageEvent(usage: final increment):
          usage = (usage ?? Usage.zero) + increment;
        case Done(stopReason: final reason):
          stopReason = reason;
        case ErrorEvent(error: final e):
          error = e;
      }
      if (event.isTerminal) break;
    }
    if (splitter != null) split(splitter.finish());
    if (usage case final used?) _reportUsage(target, used);
    if (error == null && stopReason == null) {
      error = const MalformedResponseException(
        'Antwortstrom ohne Abschluss beendet',
      );
    }
    // Incomplete tool calls of a failed stream are never executed: the
    // whole reply is discarded on error.
    return ModelReply(error == null ? blocks : const [], stopReason, error);
  }

  void _reportUsage(Resolution target, Usage used) {
    _budget.onTokens(used);
    _control.emit(
      UsageReported(
        profileId: target.profileId,
        modelId: target.modelId,
        usage: used,
        costMicros: runner.costEstimator?.estimateMicros(
          profileId: target.profileId,
          modelId: target.modelId,
          usage: used,
        ),
      ),
    );
  }

  /// Appends [text] to the last block if it is text, else starts a new
  /// text block – keeps the order of text, thinking and tool-call blocks.
  void _appendText(List<ContentBlock> blocks, String text) {
    if (blocks.isNotEmpty && blocks.last is TextBlock) {
      final last = blocks.removeLast() as TextBlock;
      blocks.add(TextBlock(last.text + text));
    } else {
      blocks.add(TextBlock(text));
    }
  }

  /// The system prompt for the current target: without memories it may
  /// not see, and after an escalation with the note on earlier tool calls.
  String _systemPrompt() {
    final memories = _state.context.memories;
    final visible = _privacy.visibleMemories();
    final base = visible.length == memories.length
        ? _state.context.systemPrompt
        : runner.contextBuilder.systemPrompt(
            memories: visible,
            speech: _state.context.speech,
          );
    if (_state.epoch == 0) return base;
    // Calls of tools this target may not see are left out (their names
    // and status are protected too).
    final shown = _privacy.perTarget ? _privacy.catalog : null;
    final before = _state.executed
        .where(
          (e) =>
              e.epoch < _state.epoch &&
              (shown == null || shown.lookup(e.call.name) != null),
        )
        .toList();
    if (before.isEmpty) return base;
    final actions = [
      for (final e in before) (call: e.call, outcome: e.outcome),
    ];
    return '$base\n\n${ContextBuilder.escalationNote(actions)}';
  }
}
