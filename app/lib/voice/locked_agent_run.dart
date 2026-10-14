import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../di/preferences.dart';
import '../di/providers.dart';

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

/// Runs a locally recognized [LockedCommand]; returns whether it worked.
typedef LockedCommandRunner = Future<bool> Function(
  LockedCommand command,
  String trigger,
);

/// Tool name of each [LockedCommand] (it only runs if its integration is
/// on and `IntegrationSpec.allowedWhileLocked`).
String lockedToolName(LockedCommand c) => switch (c) {
  LockedCommand.flashlightOn => 'flashlight__on',
  LockedCommand.flashlightOff => 'flashlight__off',
};

/// Runs [LockedCommand]s as tools without a model and without the
/// conversation: audit entry marked `whileLocked`, no history, no undo
/// card. Only tools of integrations with `allowedWhileLocked` are reachable.
final lockedCommandRunnerProvider = Provider<LockedCommandRunner>((ref) {
  return (command, trigger) async {
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
    var ok = false;
    if (tool != null) {
      final device = ref.read(deviceInfoProvider);
      try {
        final outcome = await tool.execute(
          const <String, Object?>{},
          ToolContext(
            sessionId: 'locked',
            clock: ref.read(clockProvider),
            locale: device.locale,
            timeZone: device.timeZone,
          ),
        );
        ok = !outcome.isError;
      } on Object {
        ok = false;
      }
    }
    audit.lockedToolCall(tool: name, trigger: trigger, ok: ok);
    return ok;
  };
});

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
/// (WP53): while [locked] is `true` the transcript never reaches the
/// [inner] agent (no model, no tools, no history). A flashlight command
/// ([matchLockedCommand]) runs via [runCommand]; everything else only gets
/// the fixed „unlock“ sentence, the utterance is dropped. Any trigger
/// (`TriggerKind.assistant` now, the wake word later) takes the same path.
final class LockGateAgentRun implements AgentRun {
  /// Creates the gate.
  LockGateAgentRun({
    required this.inner,
    required this.locked,
    required this.runCommand,
    required this.onRefused,
    required this.trigger,
  });

  /// The normal agent run (used when unlocked).
  final AgentRun inner;

  /// Whether the device is locked right now.
  final bool Function() locked;

  /// Executes a recognized command.
  final LockedCommandRunner runCommand;

  /// Called when a request was refused (audit, no text).
  final void Function(String trigger) onRefused;

  /// Name of the trigger that started the request (audit).
  final String Function() trigger;

  @override
  Stream<AgentEvent> run(UserInput input) {
    if (!locked()) return inner.run(input);
    return _locked(input);
  }

  Stream<AgentEvent> _locked(UserInput input) async* {
    final command = matchLockedCommand(input.text);
    final String say;
    if (command == null) {
      onRefused(trigger());
      say = LockedTexts.unlock(input.language);
    } else {
      final ok = await runCommand(command, trigger());
      say = ok
          ? LockedTexts.flashlight(
              input.language,
              on: command == LockedCommand.flashlightOn,
            )
          : LockedTexts.failed(input.language);
    }
    yield AgentTextDelta(say);
    yield AgentDone(finalText: say, stopReason: StopReason.endTurn);
  }

  @override
  void cancel() {
    // Always: the lock state may have changed since the run started.
    inner.cancel();
  }
}
