import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../agent/agent_controller.dart';
import '../di/locked_scope.dart';
import '../di/preferences.dart';
import '../di/provider_config.dart' show ProviderConfig;
import '../di/providers.dart';
import 'controller_agent_run.dart';
import 'voice_log.dart';

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

/// A request refused while locked, kept only in memory until the unlock
/// (WP114, K85): the overlay runs it after a successful unlock and drops it
/// when the unlock is cancelled, the overlay closes or [lockedPendingMaxAge]
/// has passed. Never logged, never in the audit log, never stored.
///
/// WP163 B: the entry holds the wording ([call] is `null`) **or** the one
/// tool call of that request that works only unlocked ([call] set; [text]
/// then only names the request for the display after the unlock). Same
/// mechanism, same limits; the call runs once, without a model run.
final class LockedPendingRequest {
  /// Creates the pending request.
  const LockedPendingRequest(this.text, this.at, {this.call});

  /// What was said (kept in memory only).
  final String text;

  /// When it was refused.
  final DateTime at;

  /// The tool call that waits for the unlock (tool and arguments, memory
  /// only), or `null` if the wording waits.
  final ToolCallBlock? call;

  /// How long this entry waits.
  Duration get maxAge =>
      call == null ? lockedPendingMaxAge : lockedPendingCallMaxAge;
}

/// How long a refused request waits for the unlock.
const lockedPendingMaxAge = Duration(seconds: 30);

/// How long a remembered tool call waits for the unlock (WP163 B).
const lockedPendingCallMaxAge = Duration(seconds: 60);

/// The request waiting for the unlock, if any ([LockedPendingRequest]).
final lockedPendingProvider =
    NotifierProvider<LockedPending, LockedPendingRequest?>(LockedPending.new);

/// State of [lockedPendingProvider].
final class LockedPending extends Notifier<LockedPendingRequest?> {
  @override
  LockedPendingRequest? build() => null;

  /// Remembers [text] (replaces an older one).
  void keep(String text) =>
      state = LockedPendingRequest(text, ref.read(clockProvider).now());

  /// Remembers the tool [call] of the request [text] instead of the
  /// wording (replaces an older entry; WP163 B).
  void keepCall(String text, ToolCallBlock call) => state =
      LockedPendingRequest(text, ref.read(clockProvider).now(), call: call);

  /// Drops the request.
  void clear() => state = null;

  /// The entry, once; `null` if none or too old (fail closed).
  LockedPendingRequest? take() {
    final p = state;
    state = null;
    if (p == null) return null;
    final age = ref.read(clockProvider).now().difference(p.at);
    return age > p.maxAge ? null : p;
  }
}

/// A remembered tool call, armed after the real unlock (WP163 B): the next
/// run of [LockGateAgentRun] for the same request text runs exactly this call
/// through the executor instead of the model, and the arming is used up. Set
/// by the overlay, memory only.
final lockedArmedCallProvider =
    NotifierProvider<LockedArmedCall, LockedPendingRequest?>(
      LockedArmedCall.new,
    );

/// State of [lockedArmedCallProvider].
final class LockedArmedCall extends Notifier<LockedPendingRequest?> {
  @override
  LockedPendingRequest? build() => null;

  /// Arms [request] (it must hold a call).
  // ignore: use_setters_to_change_properties
  void arm(LockedPendingRequest request) => state = request;

  /// Disarms.
  void clear() => state = null;

  /// The call armed for [text], once (`null` otherwise; a mismatch keeps
  /// the arming).
  ToolCallBlock? takeFor(String text) {
    final r = state;
    if (r == null || r.text != text) return null;
    state = null;
    final age = ref.read(clockProvider).now().difference(r.at);
    return age > r.maxAge ? null : r.call;
  }
}

/// The current request on the locked device and the answer to it (WP163,
/// ADR 0022 L2/L3): what the overlay may show while locked. Only what was
/// heard and what is spoken anyway; never tool names, arguments or results,
/// never a history. Memory only, not stored, not logged.
final class LockedExchange {
  /// Creates the exchange.
  const LockedExchange(this.request, {this.answer});

  /// What was said (speech-to-text result).
  final String request;

  /// What the assistant answers (also spoken); `null` while the answer is
  /// pending or when the run ended without one (cancelled).
  final String? answer;
}

/// The one current [LockedExchange] of the locked overlay, if any.
final lockedExchangeProvider =
    NotifierProvider<LockedExchangeNotifier, LockedExchange?>(
      LockedExchangeNotifier.new,
    );

/// State of [lockedExchangeProvider]; a new request replaces the old one.
final class LockedExchangeNotifier extends Notifier<LockedExchange?> {
  @override
  LockedExchange? build() => null;

  /// A new request starts (replaces request and answer of the one before).
  void begin(String request) => state = LockedExchange(request);

  /// The answer to the current request (ignored without a request).
  void answer(String text) {
    final e = state;
    if (e == null) return;
    state = LockedExchange(e.request, answer: text);
  }

  /// Drops request and answer (unlock, overlay closed).
  void clear() => state = null;
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

/// Runs a call that waited for the unlock ([LockedPendingRequest.call]).
typedef DeferredCallRunner = Future<ToolOutcome> Function(ToolCallBlock call);

/// Runs the remembered call of WP163 B once, after the real unlock, through
/// the normal executor (policy of the **unlocked** device, audit as any call,
/// timeout) and without a model. A confirmation is never asked here (the
/// call was allowed without one while locked): fail-closed, declined.
final deferredCallRunnerProvider = Provider<DeferredCallRunner>((ref) {
  return (call) async {
    final ProviderConfig? providers;
    try {
      providers = await ref.read(providerConfigProvider.future);
      await ref.read(toolRegistryReadyProvider.future);
    } on Object {
      return ToolOutcome.error('Nicht verfügbar.');
    }
    if (providers == null) return ToolOutcome.error('Nicht verfügbar.');
    final registry = ref.read(toolRegistryProvider);
    final device = ref.read(deviceInfoProvider);
    final executor = ToolExecutor(
      catalog: registry.catalogFor(
        providers.lowestPrivacy,
        sessionId: lockedSessionId,
      ),
      policy: ref.read(riskPolicyProvider),
      audit: ref.read(auditRecorderProvider),
    );
    var outcome = ToolOutcome.error('Nicht ausgeführt.');
    try {
      await for (final event in executor.invokeAll(
        [call],
        ToolContext(
          sessionId: lockedSessionId,
          clock: ref.read(clockProvider),
          locale: device.locale,
          timeZone: device.timeZone,
        ),
      )) {
        switch (event) {
          case ConfirmationNeeded():
            event.respond(false);
          case ToolFinished():
            outcome = event.outcome;
          case ToolStarted():
        }
      }
    } on Object {
      outcome = ToolOutcome.error('Nicht ausgeführt.');
    }
    return outcome;
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

/// The tools of the executor mark `WorksOnlyUnlocked` that start a
/// navigation: the held-back sentence then says „Zum Navigieren“, otherwise
/// the generic one (WP163 B).
const lockedNavigationTools = {'maps__navigate', 'location__navigate_to'};

/// Fixed sentences of the lock screen (no content, three languages).
abstract final class LockedTexts {
  /// Said for everything but a flashlight command.
  static String unlock(String? language) => switch (_lang(language)) {
    'fr' => 'Veuillez déverrouiller le téléphone.',
    'en' => 'Please unlock the phone.',
    _ => 'Bitte entsperre das Telefon.',
  };

  /// Said after a flashlight command.
  static String flashlight(String? language, {required bool on}) =>
      switch (_lang(language)) {
        'fr' => on ? 'Lampe allumée.' : 'Lampe éteinte.',
        'en' => on ? 'Flashlight on.' : 'Flashlight off.',
        _ => on ? 'Taschenlampe an.' : 'Taschenlampe aus.',
      };

  /// Said when a call that works only unlocked (WP163 B) waits for the
  /// unlock: [navigation] names the navigation, else generic.
  static String deferred(String? language, {required bool navigation}) =>
      switch (_lang(language)) {
        'fr' =>
          navigation
              ? 'Veuillez déverrouiller pour naviguer.'
              : 'Veuillez déverrouiller pour cela.',
        'en' =>
          navigation ? 'Please unlock to navigate.' : 'Please unlock for that.',
        _ =>
          navigation
              ? 'Zum Navigieren bitte entsperren.'
              : 'Dafür bitte entsperren.',
      };

  /// The command did not work (no LED, camera busy).
  static String failed(String? language) => switch (_lang(language)) {
    'fr' => 'Cela ne marche pas.',
    'en' => 'That did not work.',
    _ => 'Das hat nicht geklappt.',
  };

  static String _lang(String? language) =>
      (language ?? 'de').toLowerCase().split(RegExp('[-_]')).first;
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
    var refused = false;
    var anyDone = false;
    ToolCallBlock? deferred;
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
          deferred ??= event.call;
        } else if (event.outcome.summary == ToolExecutor.unlockSummary) {
          refused = true;
        } else if (!event.outcome.isError) {
          anyDone = true;
        }
      }
      yield event;
      if (deferred != null) break;
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
    if (refused) {
      if (anyDone) {
        onPartlyDone?.call(trigger());
      } else {
        onRefused(trigger(), input);
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
  runDeferred: (call) => ref.read(deferredCallRunnerProvider)(call),
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
