/// One model call of an agent run (concept: „Agent-Schleife“, K8 e): the
/// request as the current target may see it (system prompt with visible
/// memories and the escalation note, catalog, redacted messages), streaming
/// of text and thinking, and the token count. Internal to `wendelin_agent`,
/// not exported.
library;

import 'package:wendelin_core/wendelin_core.dart';

import '../agent_runner_texts.dart';
import '../context_builder.dart';
import '../provider_resolver.dart';
import 'attestation_gate.dart';
import 'privacy_scope.dart';
import 'run_budget.dart';
import 'run_config.dart';
import 'run_state.dart';
import 'spoken_block.dart';
import 'spoken_check.dart';

/// Result of one model call.
final class ModelReply {
  /// Creates the reply.
  ModelReply(this.blocks, this.stopReason, this.error, [this.step]);

  /// The verification step of this answer (`null` only if none was begun);
  /// the tool round of this answer must use it, not the latest step.
  final AttestationStep? step;

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
    this._attest,
  );

  /// The runner (context builder, session, cost estimator).
  final RunConfig runner;
  final RunState _state;
  final PrivacyScope _privacy;
  final RunBudget _budget;
  final RunControl _control;
  final AttestationGate _attest;

  /// Calls the model of the current target and streams its answer.
  Future<ModelReply> call() async {
    // Invariant: the floor follows the taint before every model call.
    _privacy.raiseFloorToTaint();
    _state.modelCalled = true;
    final config = runner.contextBuilder.config;
    final target = _state.current;
    final catalog = _privacy.catalog;
    // A profile without tools (WP63) gets none; the history then reads as text.
    final noTools = !target.provider.caps.tools;
    final tools = noTools ? const <ToolSpec>[] : catalog.activeSpecs();
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

    final splitter = _state.speech == SpeechStyle.twoVersions
        ? SpokenBlockSplitter()
        : null;
    void text(String delta) {
      if (delta.isEmpty) return;
      _control.emit(AgentTextDelta(delta));
      _appendText(blocks, delta);
    }

    // Checked mode after foreign content: the spoken text waits for the
    // verdict (the speech output holds the written text back meanwhile).
    String? held;
    void split(SplitText r) {
      if (r.spoken case final spoken?) {
        if (_state.spokenVersion == SpokenVersion.checked &&
            _state.untrustedSeen) {
          held = spoken;
          _control.emit(const AgentSpokenHold());
        } else {
          _control.emit(AgentSpokenText(spoken));
        }
      }
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
          // Server-side tool results (web search) are third-party text.
          _state.untrustedSeen = true;
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
    if (held case final spoken? when error == null && stopReason != null) {
      await _checkSpoken(target, spoken, _writtenText(blocks));
    }
    if (error == null && stopReason == null) {
      error = const MalformedResponseException(
        'Antwortstrom ohne Abschluss beendet',
      );
    }
    // The text is complete: speech reads the last sentence now, not after the
    // receipt (WP81). Tool calls continue the answer after the round.
    if (error == null &&
        stopReason != null &&
        stopReason != StopReason.pauseTurn &&
        !blocks.any((b) => b is ToolCallBlock)) {
      _control.emit(const AgentTextComplete());
    }
    final step = await _reportAttestation(
      target,
      request,
      blocks,
      failed: error != null,
    );
    // Incomplete tool calls of a failed stream are never executed: the
    // whole reply is discarded on error.
    return ModelReply(
      error == null ? blocks : const [],
      stopReason,
      error,
      step,
    );
  }

  String _writtenText(List<ContentBlock> blocks) =>
      blocks.whereType<TextBlock>().map((b) => b.text).join();

  /// Checks the held spoken text against the written answer of this call
  /// (WP55): only a match releases it; the cost counts like any model call.
  Future<void> _checkSpoken(
    Resolution target,
    String spoken,
    String written,
  ) async {
    final verdict =
        await SpokenCheck(runner.contextBuilder.config.spokenCheckTimeout).run(
          target.provider,
          target.modelId,
          spoken: spoken,
          written: written,
          parent: _control.token,
          language: _state.language,
          sessionId: runner.sessionId,
        );
    _control.throwIfAborted();
    if (verdict.usage case final used?) _reportUsage(target, used);
    _control.emit(
      AgentSpokenVerdict(accepted: verdict.match, reason: verdict.reason),
    );
    if (verdict.match) _control.emit(AgentSpokenText(spoken));
  }

  /// Remembers the verification of the answer; without tool calls nothing
  /// waits for it, so it is reported now. With tool calls the tool round
  /// reports it (external tools wait for it).
  Future<AttestationStep> _reportAttestation(
    Resolution target,
    ChatRequest request,
    List<ContentBlock> blocks, {
    required bool failed,
  }) async {
    final step = _attest.begin(
      target.provider,
      request,
      failed: failed,
      sink: _control,
      profileId: target.profileId,
    );
    if (failed || !blocks.any((b) => b is ToolCallBlock)) {
      await _attest.settle(step);
    }
    return step;
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
  /// not see, with the speech hint of the run (stage 2 drops to stage 1 after
  /// an untrusted tool result; only the changing end of the prompt differs
  /// for the cache).
  String _systemPrompt() {
    final base = _basePrompt();
    return _state.current.provider.caps.tools
        ? base
        : '$base\n\n${AgentRunnerTexts.noToolsNote}';
  }

  String _basePrompt() {
    final memories = _state.context.memories;
    final visible = _privacy.visibleMemories();
    final speech = _state.speech;
    // A tool section only goes to a target whose catalog offers the tool
    // (privacy level per target, K10).
    final all = _state.context.sections;
    final sections = [
      for (final s in all)
        if (_privacy.catalog.lookup(s.toolName) != null) s,
    ];
    return visible.length == memories.length &&
            speech == _state.context.speech &&
            sections.length == all.length
        ? _state.context.systemPrompt
        : runner.contextBuilder.systemPrompt(
            memories: visible,
            speech: speech,
            sections: sections,
          );
  }
}
