import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../agent/agent_controller.dart';
import '../di/locked_scope.dart';
import '../di/preferences.dart';
import '../di/providers.dart';
import 'controller_agent_run.dart';
import 'locked_deferred.dart';
import 'voice_log.dart';

export 'locked_deferred.dart';

/// Whether the device is locked while the assistant overlay listens
/// (WP53, K16). Set by the overlay; while `true` the voice pipeline does
/// not reach the agent: [LockGateAgentRun] answers on its own.
final lockedModeProvider = NotifierProvider<LockedMode, bool>(LockedMode.new);

/// State of [lockedModeProvider].
final class LockedMode extends Notifier<bool> {
  @override
  bool build() => false;

  /// Sets the lock state the voice pipeline works under.
  // ignore: use_setters_to_change_properties
  void set(bool locked) => state = locked;
}

/// Counts requests refused while locked; the overlay then offers the
/// unlock (after the spoken hint).
final lockedRefusalsProvider = NotifierProvider<LockedRefusals, int>(
  LockedRefusals.new,
);

/// State of [lockedRefusalsProvider].
final class LockedRefusals extends Notifier<int> {
  @override
  int build() => 0;

  /// One more refused request.
  void bump() => state++;
}

/// The device is unlocked (or the overlay ends): the voice pipeline reaches
/// the agent again and the locked exchange is not shown any more.
void endLockedMode(WidgetRef ref) {
  ref.read(lockedModeProvider.notifier).set(false);
  ref.read(lockedExchangeProvider.notifier).clear();
}

/// How a locally recognized [LockedCommand] ended.
enum LockedCommandResult {
  /// The tool ran.
  done,

  /// The tool ran but failed (no LED, camera busy, timeout) or is not
  /// reachable.
  failed,

  /// The policy needs the unlocked device (the level of the tool, WP154):
  /// nothing ran.
  needsUnlock,
}

/// Runs a locally recognized [LockedCommand] through policy and executor.
typedef LockedCommandRunner = Future<LockedCommandResult> Function(
  LockedCommand command,
  String trigger,
  AccessContext access,
);

/// Tool name of each [LockedCommand] (it only runs if its integration is
/// on and `IntegrationSpec.allowedWhileLocked`).
///
/// **Approval list for a locked device (WP114, K85), reviewed per tool:**
/// - `flashlight__on`, `flashlight__off`: allowed. Only the torch state of
///   the phone changes; no personal data is read, nothing leaves the device,
///   nobody else is affected, no permission prompt, the effect is visible at
///   once and reversible by the other command.
/// - `flashlight__toggle`: not reachable (no spoken command maps to it).
/// - Everything else is refused while locked, because it reads personal data
///   (calendar, contacts, notes, memory, lists, messages, location), acts on
///   others (calls, messages, mail, smart home) or costs money/network
///   (search, model). New entries need a review of the same questions.
/// `test/overlay/locked_approval_list_test.dart` pins the list.
String lockedToolName(LockedCommand c) => switch (c) {
  LockedCommand.flashlightOn => 'flashlight__on',
  LockedCommand.flashlightOff => 'flashlight__off',
};

/// Runs [LockedCommand]s as tools without a model and without the
/// conversation: audit entry marked `whileLocked`, no history, no undo
/// card. Only tools of integrations with `allowedWhileLocked` are reachable,
/// and like every call the tool goes through the **policy and the executor**
/// (WP154 L2): the level of the tool decides locked (the flashlight is A by
/// default), a tool the user raised to B–D, a confirm-only mark or a
/// disabled tool does not run, and a tool that hangs ends at the executor's
/// timeout.
final lockedCommandRunnerProvider = Provider<LockedCommandRunner>((ref) {
  return (command, trigger, access) async {
    final name = lockedToolName(command);
    final demo = ref.read(demoModeProvider);
    final enabled = ref.read(enabledIntegrationsProvider);
    final prefs = ref.read(toolPrefsProvider);
    final integrations = ref.read(integrationsProvider);
    final audit = ref.read(auditRecorderProvider);
    Tool? tool;
    for (final spec in ref.read(integrationSpecsProvider)) {
      if (!spec.allowedWhileLocked) continue;
      if (!demo && !enabled.contains(spec.id)) continue;
      for (final t in integrations[spec.id]?.tools ?? const <Tool>[]) {
        if (t.name == name && !prefs.disabled.contains(name)) tool = t;
      }
    }
    if (tool == null) {
      audit.lockedToolCall(tool: name, trigger: trigger, ok: false);
      return LockedCommandResult.failed;
    }
    final device = ref.read(deviceInfoProvider);
    final executor = ToolExecutor(
      catalog: _OneTool(tool),
      policy: ref.read(riskPolicyProvider),
      access: access,
    );
    var result = LockedCommandResult.failed;
    try {
      final events = executor.invokeAll(
        [ToolCallBlock(id: 'locked', name: name, argumentsJson: '{}')],
        ToolContext(
          sessionId: 'locked',
          clock: ref.read(clockProvider),
          locale: device.locale,
          timeZone: device.timeZone,
        ),
      );
      await for (final event in events) {
        switch (event) {
          // Never asked while locked; fail-closed if it ever is.
          case ConfirmationNeeded():
            event.respond(false);
          case ToolFinished(:final outcome):
            result = !outcome.isError
                ? LockedCommandResult.done
                : outcome.summary == ToolExecutor.unlockSummary
                ? LockedCommandResult.needsUnlock
                : LockedCommandResult.failed;
          case ToolStarted():
        }
      }
    } on Object {
      result = LockedCommandResult.failed;
    }
    // A refusal is logged by the gate ([LockGateAgentRun.onRefused]).
    if (result != LockedCommandResult.needsUnlock) {
      audit.lockedToolCall(
        tool: name,
        trigger: trigger,
        ok: result == LockedCommandResult.done,
      );
    }
    return result;
  };
});

/// The single tool of a locked command as a catalog.
final class _OneTool implements ToolCatalog {
  const _OneTool(this.tool);

  final Tool tool;

  @override
  List<ToolSpec> activeSpecs() => [tool.spec];

  @override
  Tool? lookup(String name) => name == tool.name ? tool : null;
}

/// The agent run of the voice pipeline with the lock gate in front
/// (WP53, WP154 L2): while [locked] is `true` the transcript reaches the
/// [inner] agent never. A flashlight command ([matchLockedCommand]) runs via
/// [runCommand] (policy and executor, no model). Anything else runs the
/// model only if [modelRun] offers a run (at least one tool or Home
/// Assistant device is allowed locked, [LockedScope]) and then only with
/// those tools; otherwise it only gets the fixed „unlock“ sentence and the
/// utterance is remembered 30 s ([onRefused], K92). A tool call the policy
/// refuses („Entsperren nötig“) remembers it the same way, unless a tool
/// of that run already ran ([onPartlyDone]: no double execution). Any trigger
/// (`TriggerKind.assistant`, the wake word) takes the same path.
final class LockGateAgentRun implements AgentRun {
  /// Creates the gate.
  LockGateAgentRun({
    required this.inner,
    required this.locked,
    required this.runCommand,
    required this.onRefused,
    required this.trigger,
    this.modelRun,
    this.onPartlyDone,
    this.onDeferred,
    this.takeArmed,
    this.runDeferred,
    this.onRequest,
    this.onAnswer,
    this.log,
  });

  /// The normal agent run (used when unlocked).
  final AgentRun inner;

  /// Whether the device is locked right now.
  final bool Function() locked;

  /// Executes a recognized command.
  final LockedCommandRunner runCommand;

  /// Called when a request was refused: [trigger] for the audit log (no
  /// text there), [input] so the overlay can run it after the unlock
  /// (WP114; memory only).
  final void Function(String trigger, UserInput input) onRefused;

  /// The run for a request on a locked device in [access] (the voice from
  /// [AccessContext.lockedFor]), or `null` if nothing beyond the local commands is allowed.
  /// `null` here = never a model while locked (tests, K85 behaviour).
  final Future<AgentRun?> Function(AccessContext access)? modelRun;

  /// Called when a model run did part of the request and the policy turned
  /// down the rest: the unlock is offered but the request is NOT remembered
  /// (no double run, [trigger] for the audit log).
  final void Function(String trigger)? onPartlyDone;

  /// A tool call that works only unlocked (WP163 B) was held back by the
  /// executor: the overlay remembers it for the unlock ([call] only in
  /// memory; [trigger] for the audit log).
  final void Function(String trigger, UserInput input, ToolCallBlock call)?
  onDeferred;

  /// After the unlock: the remembered call armed for this request text, once
  /// (see [lockedArmedCallProvider]); it runs instead of the model.
  final ToolCallBlock? Function(String text)? takeArmed;

  /// Runs such a call through the executor of the unlocked device.
  final DeferredCallRunner? runDeferred;

  /// A request arrives while locked (WP163): the overlay shows it. Not
  /// called when unlocked.
  final void Function(UserInput input)? onRequest;

  /// The answer of a locked request, exactly the text of a model run, the
  /// local command or the fixed sentence (WP163). Not called if the run is
  /// cancelled before it ends.
  final void Function(String text)? onAnswer;

  /// Diagnostics without any content (`locked-cmd …`).
  final void Function(String line)? log;

  /// Name of the trigger that started the request (audit).
  final String Function() trigger;

  AgentRun? _lockedRun;

  @override
  Stream<AgentEvent> run(UserInput input) {
    if (!locked()) {
      final call = takeArmed?.call(input.text);
      if (call != null && runDeferred != null) return _afterUnlock(call, input);
      return inner.run(input);
    }
    return _locked(input);
  }

  // The call that waited for the unlock: once, no model, result spoken.
  Stream<AgentEvent> _afterUnlock(ToolCallBlock call, UserInput input) async* {
    ToolOutcome outcome;
    try {
      outcome = await runDeferred!(call);
    } on Object {
      outcome = ToolOutcome.error('failed');
    }
    yield* _say(
      outcome.isError
          ? LockedTexts.failed(input.language)
          : outcome.summary ?? outcome.text,
      answer: false,
    );
  }

  Stream<AgentEvent> _locked(UserInput input) async* {
    onRequest?.call(input);
    final command = matchLockedCommand(input.text);
    // Who is speaking (WP154 L3): only a recognized voice counts for level B.
    final access = AccessContext.lockedFor(input);
    log?.call(
      'locked-cmd match=${command?.name ?? 'none'} '
      'voice=${access.speakerRecognized ? 'known' : 'unknown'}',
    );
    if (command != null) {
      final result = await runCommand(command, trigger(), access);
      if (result == LockedCommandResult.needsUnlock) {
        onRefused(trigger(), input);
      }
      yield* _say(switch (result) {
        LockedCommandResult.done => LockedTexts.flashlight(
          input.language,
          on: command == LockedCommand.flashlightOn,
        ),
        LockedCommandResult.needsUnlock => LockedTexts.unlock(input.language),
        LockedCommandResult.failed => LockedTexts.failed(input.language),
      });
      return;
    }
    AgentRun? model;
    try {
      model = await modelRun?.call(access);
    } on Object {
      model = null; // fail-closed: refused as before
    }
    log?.call('locked-model run=${model != null}');
    if (model == null) {
      onRefused(trigger(), input);
      yield* _say(LockedTexts.unlock(input.language));
      return;
    }
    _lockedRun = model;
    final tally = _Tally();
    yield* _modelRun(model, input, tally);
    final deferred = tally.deferred;
    if (deferred != null) {
      // Only this call waits (also if another tool of the run already ran:
      // no double run, ADR 0022 a); the model says nothing more.
      onDeferred?.call(trigger(), input, deferred);
      yield* _say(
        LockedTexts.deferred(
          input.language,
          navigation: lockedNavigationTools.contains(deferred.name),
        ),
      );
      return;
    }
    // A call the policy turned down: the unlock is offered. The request only
    // waits for it if nothing ran yet; otherwise the repeat after the unlock
    // would run the finished part twice (the answer names what is done).
    if (tally.refused) {
      if (tally.anyDone) {
        onPartlyDone?.call(trigger());
      } else {
        onRefused(trigger(), input);
      }
    }
  }

  // The model run of a locked request: events pass on, [t] records what the
  // tool calls did. Ends at the first deferred call.
  Stream<AgentEvent> _modelRun(
    AgentRun model,
    UserInput input,
    _Tally t,
  ) async* {
    // The `<spoken>` text of the current segment, as the pipeline speaks it
    // (reset like there: new segment after a tool call, text reset).
    String? spoken;
    await for (final event in model.run(input)) {
      switch (event) {
        case AgentSpokenText(:final text):
          spoken = text;
        case AgentTextReset() || ToolCallStarted() || ToolCallFinished():
          spoken = null;
        default:
      }
      if (event is ToolCallFinished) {
        if (event.outcome.summary == ToolExecutor.deferredSummary) {
          // Works only unlocked: the run ends here (see below). The agent
          // itself sends no further request ([ToolOutcome.endsRun]).
          t.deferred ??= event.call;
        } else if (event.outcome.summary == ToolExecutor.unlockSummary) {
          t.refused = true;
        } else if (!event.outcome.isError) {
          t.anyDone = true;
        }
      }
      yield event;
      if (t.deferred != null) return;
      // After the yield: a cancelled stream ends there and records nothing.
      // Shown is what is spoken: the `<spoken>` text if the run has one, else
      // the final text; a failed run shows the wording the pipeline speaks.
      switch (event) {
        case AgentDone(:final finalText):
          onAnswer?.call(spoken ?? finalText);
        case AgentFailed(:final error, :final message)
            when error != AgentErrorKind.cancelled:
          onAnswer?.call(VoiceTexts.of(input.language).failure(error, message));
        default:
      }
    }
  }

  Stream<AgentEvent> _say(String say, {bool answer = true}) async* {
    yield AgentTextDelta(say);
    yield AgentDone(finalText: say, stopReason: StopReason.endTurn);
    if (answer) onAnswer?.call(say);
  }

  @override
  void cancel() {
    // Always: the lock state may have changed since the run started.
    inner.cancel();
    _lockedRun?.cancel();
  }
}

/// What the tool calls of one locked model run did.
final class _Tally {
  bool refused = false;
  bool anyDone = false;
  ToolCallBlock? deferred;
}

/// The lock gate with its app wiring (voice pipeline): runs of
/// [lockedCommandRunnerProvider], refusals go to the audit log (no text),
/// the wording waits in [lockedPendingProvider] (memory only, WP114).
LockGateAgentRun lockGateFor(
  Ref ref, {
  required AgentRun inner,
  required String Function() trigger,
}) => LockGateAgentRun(
  inner: inner,
  locked: () => ref.read(lockedModeProvider),
  runCommand: (c, t, a) => ref.read(lockedCommandRunnerProvider)(c, t, a),
  modelRun: (access) async {
    final scope = await ref.read(lockedScopeProvider)(access);
    if (scope == null) return null;
    return ControllerAgentRun(
      ref.read(agentControllerProvider.notifier),
      trigger: trigger,
      locked: scope,
    );
  },
  onRefused: (t, input) {
    ref.read(auditRecorderProvider).lockedRefused(trigger: t);
    ref.read(lockedPendingProvider.notifier).keep(input.text);
    ref.read(lockedRefusalsProvider.notifier).bump();
  },
  onDeferred: (t, input, call) {
    ref.read(auditRecorderProvider).lockedRefused(trigger: t);
    ref.read(lockedPendingProvider.notifier).keepCall(input.text, call);
    ref.read(lockedRefusalsProvider.notifier).bump();
  },
  takeArmed: (text) => ref.read(lockedArmedCallProvider.notifier).takeFor(text),
  runDeferred: (call) async {
    final outcome = await ref.read(deferredCallRunnerProvider)(call);
    ref
        .read(agentControllerProvider.notifier)
        .finishHeldBackTool(call, outcome);
    return outcome;
  },
  onPartlyDone: (t) {
    ref.read(auditRecorderProvider).lockedRefused(trigger: t);
    ref.read(lockedRefusalsProvider.notifier).bump();
  },
  onRequest: (input) =>
      ref.read(lockedExchangeProvider.notifier).begin(input.text),
  onAnswer: (text) => ref.read(lockedExchangeProvider.notifier).answer(text),
  trigger: trigger,
  log: voiceLog,
);
