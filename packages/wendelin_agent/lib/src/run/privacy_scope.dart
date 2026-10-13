/// Privacy and taint of one agent run (K10, K13, ADR 0009): which tools and
/// which parts of the conversation and the memory the current target may
/// see, the rise of the run's privacy floor to the taint level, and the
/// user's consent to go below that floor. Internal to `wendelin_agent`, not
/// exported.
library;

import 'package:collection/collection.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../agent_runner.dart';
import '../ports.dart';
import '../provider_resolver.dart';
import 'run_state.dart';

/// Answers „what may the current target see?“ for one run.
///
/// Invariants:
/// - The run's privacy floor never sinks; [raiseFloorToTaint] only raises
///   it (via [RunState.raiseFloor]).
/// - Once the current target sees private content (an earlier private turn
///   or a memory entry with a floor), the floor rises to that taint level
///   before the next model call.
/// - Tools outside the current target's [catalog] are never offered, and
///   their calls and results in the history are redacted ([messagesFor]).
/// - Earlier private turns above the target's level are replaced by
///   placeholders, unless the user consented to go below this run's floor
///   and that floor covers them ([hiddenFor]).
final class PrivacyScope {
  /// Creates the scope of [runner]'s run with [_state].
  PrivacyScope(this.runner, this._state);

  /// The runner (catalog per level, memory floor).
  final AgentRunner runner;
  final RunState _state;

  bool _consentDeclined = false;

  /// The user agreed to hand this run to a target below its privacy floor;
  /// earlier private turns up to that floor are then visible to it.
  bool _belowFloorConsented = false;

  /// Ids of calls refused because the target could not see the tool.
  final Set<String> _refused = {};

  Resolution get _current => _state.current;

  /// Whether every target has its own tool catalog
  /// ([AgentRunner.catalogFor]).
  bool get perTarget => runner.catalogFor != null;

  /// The tool catalog of the current target.
  ToolCatalog get catalog =>
      runner.catalogFor?.call(_current.privacy) ??
      runner.contextBuilder.catalog;

  /// The user declined going below the floor in this run; a „no“ stands.
  bool get consentDeclined => _consentDeclined;

  /// The user agreed to a hand-over; [belowFloor] = to a target below the
  /// run's floor.
  void consented({required bool belowFloor}) {
    if (belowFloor) _belowFloorConsented = true;
  }

  /// The user declined going below the run's floor.
  void declined() => _consentDeclined = true;

  /// Marks call [callId] as refused (the target may not see its tool).
  void refuse(String callId) => _refused.add(callId);

  /// Whether this run holds results of tools [next] may not see: it gets
  /// them redacted, but the user decides whether to hand over at all.
  bool holdsProtectedFor(Resolution next) {
    final nextCatalog = runner.catalogFor?.call(next.privacy);
    return nextCatalog != null &&
        _state.executed.any(
          (e) =>
              !isDeclined(e.outcome) && nextCatalog.lookup(e.call.name) == null,
        );
  }

  /// The memory entries the current target may see in the system prompt.
  List<MemoryItem> visibleMemories() {
    // Memory entries of private runs only for targets of their level.
    final memories = _state.context.memories;
    // The memory's own floor ([AgentRunner.memoryFloor], a tool-catalog
    // boundary like K10) holds even after consent to go below the run's
    // floor; only the entries' own floors (K13 e) can be lifted that way.
    final all = runner.memoryFloor;
    final memoryAllowed = all == null || _current.privacy.isAtLeast(all);
    return [
      for (final m in memories)
        if (memoryAllowed && !hiddenFor(_memoryFloor(m))) m,
    ];
  }

  /// [RunState.messages] as [catalog]'s target may see them. A protected
  /// section starts after a hidden result and ends with the next user
  /// message; in it also calls of visible tools are hidden.
  ///
  /// With per-target catalogs, calls to tools outside [catalog] are redacted
  /// (arguments `{}`, result [AgentRunnerTexts.redactedResult]) – they may
  /// hold sensitive data from a more private target or an earlier run – and
  /// so is every assistant text, thinking or provider block that follows
  /// such a result up to the next user message
  /// ([AgentRunnerTexts.placeholder]): the answer was built from the
  /// protected data. Without any tools for the target ([hasTools] false)
  /// tool calls and results become plain text, because APIs reject tool
  /// blocks in a request without tools.
  List<Message> messagesFor(ToolCatalog catalog, {required bool hasTools}) {
    final hidden = <String>{};
    var tainted = false;
    // Hidden: calls of tools outside the catalog (refused calls never ran,
    // their result is our own error text) and, in a protected section,
    // every call – its arguments may quote the protected result.
    bool secret(ToolCallBlock c) =>
        perTarget &&
        (tainted ||
            (!_refused.contains(c.id) && catalog.lookup(c.name) == null));
    final out = <Message>[];
    for (final m in _withoutPrivateHistory()) {
      if (m.role == Role.user) tainted = false;
      var taintsNext = false;
      final blocks = <ContentBlock>[];
      for (final b in m.content) {
        switch (b) {
          case ToolCallBlock() when secret(b):
            hidden.add(b.id);
            blocks.add(
              hasTools
                  ? ToolCallBlock(id: b.id, name: b.name, argumentsJson: '{}')
                  : TextBlock('[Tool-Aufruf: ${b.name}]'),
            );
          case ToolCallBlock() when !hasTools:
            blocks.add(
              TextBlock('[Tool-Aufruf: ${b.name} ${b.argumentsJson}]'),
            );
          case ToolResultBlock() when hidden.contains(b.callId):
            taintsNext = true;
            blocks.add(
              hasTools
                  ? ToolResultBlock(
                      callId: b.callId,
                      content: const [
                        TextBlock(AgentRunnerTexts.redactedResult),
                      ],
                    )
                  : const TextBlock(
                      '[Tool-Ergebnis: ${AgentRunnerTexts.redactedResult}]',
                    ),
            );
          case ToolResultBlock() when !hasTools:
            final text = b.content.whereType<TextBlock>().map((t) => t.text);
            blocks.add(TextBlock('[Tool-Ergebnis: ${text.join()}]'));
          case TextBlock() when tainted && m.role == Role.assistant:
            if (blocks.lastOrNull !=
                const TextBlock(AgentRunnerTexts.placeholder)) {
              blocks.add(const TextBlock(AgentRunnerTexts.placeholder));
            }
          case ThinkingBlock() || ProviderBlock()
              when tainted && m.role == Role.assistant:
            break; // built from protected data
          case _:
            blocks.add(b);
        }
      }
      if (taintsNext) tainted = true;
      final role = !hasTools && m.role == Role.tool ? Role.user : m.role;
      if (blocks.isEmpty && m.content.isNotEmpty) {
        // Everything was protected (e.g. only thinking): keep the turn, not
        // its content.
        blocks.add(const TextBlock(AgentRunnerTexts.placeholder));
      }
      out.add(blocks.isEmpty ? m : Message(role, blocks));
    }
    return out;
  }

  /// [RunState.messages] with earlier private turns the current target may
  /// not see replaced by [AgentRunnerTexts.privateHidden]: a user
  /// placeholder and, if the turn had an answer, one assistant placeholder
  /// (tool calls and results disappear together, so pairs stay intact).
  ///
  /// A message is hidden when its floor is above the target's level, unless
  /// the user agreed to go below this run's floor and that floor covers it.
  List<Message> _withoutPrivateHistory() {
    final hidden = hiddenFor;
    final out = <Message>[];
    var hiding = false;
    var answered = false;
    for (final m in _state.messages) {
      if (!hidden(m.privacyFloor)) {
        hiding = false;
        out.add(m);
        continue;
      }
      if (m.role == Role.user || !hiding) {
        out.add(Message.user(AgentRunnerTexts.privateHidden));
        hiding = true;
        answered = false;
        if (m.role == Role.user) continue;
      }
      if (!answered) {
        out.add(Message.assistantText(AgentRunnerTexts.privateHidden));
        answered = true;
      }
    }
    return out;
  }

  /// Whether content with privacy [floor] (an earlier private turn or
  /// memory entry) is hidden from the current target: its level is below
  /// [floor], and the user did not agree to go below this run's floor
  /// covering it.
  bool hiddenFor(PrivacyLevel? floor) {
    final runFloor = _current.privacyFloor;
    return floor != null &&
        !_current.privacy.isAtLeast(floor) &&
        !(_belowFloorConsented &&
            runFloor != null &&
            runFloor.isAtLeast(floor));
  }

  /// The floor of memory entry [m]: its own, at least [AgentRunner.
  /// memoryFloor].
  PrivacyLevel? _memoryFloor(MemoryItem m) {
    final own = m.privacyFloor;
    final all = runner.memoryFloor;
    if (own == null) return all;
    if (all == null) return own;
    return own.isAtLeast(all) ? own : all;
  }

  /// Taint propagation: once the current target sees private content (an
  /// earlier private turn or memory entry), whatever this run produces may
  /// contain it. The run's floor rises to the highest such floor, so its
  /// messages are stored with it, tools persist with it, and escalations
  /// below it need consent.
  void raiseFloorToTaint() {
    PrivacyLevel? taint;
    for (final floor in [
      for (final m in _state.messages) m.privacyFloor,
      for (final m in _state.context.memories) _memoryFloor(m),
    ]) {
      if (floor == null || hiddenFor(floor)) continue;
      if (taint == null || floor.isAtLeast(taint)) taint = floor;
    }
    // Invariant: after seeing protected content the floor rises to the
    // taint level (and never sinks, see [RunState.raiseFloor]).
    if (taint != null) _state.raiseFloor(taint);
  }
}
