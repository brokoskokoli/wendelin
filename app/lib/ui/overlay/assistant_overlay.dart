import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../agent/agent_controller.dart';
import '../../di/providers.dart';
import '../../di/voice_providers.dart';
import '../../platform/assistant_platform.dart';
import '../../voice/voice_components.dart';
import '../../voice/voice_controller.dart';
import '../design/design.dart';
import '../screens/confirmation_sheet.dart';
import '../voice/microphone_access.dart';
import 'overlay_sheet.dart';

/// Root widget of the assistant overlay (Dart entrypoint `assistantMain`,
/// started by `AssistantActivity` with a transparent window).
class AssistantOverlayApp extends StatelessWidget {
  /// Creates the overlay app.
  const AssistantOverlayApp({super.key, this.autoStart = true});

  /// Whether the overlay starts listening right away (off for goldens).
  final bool autoStart;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Wendelin',
    debugShowCheckedModeBanner: false,
    theme: buildWendelinTheme(),
    color: WColors.transparent,
    home: AssistantOverlayScreen(autoStart: autoStart),
  );
}

/// The assistant overlay (docs/design/screens/overlay): a sheet over the
/// lower part of the screen, the rest stays transparent (tapping it
/// closes the overlay).
///
/// Every invocation of the assistant is a `TriggerKind.assistant`
/// ([AssistantTriggerSource]) and starts listening. **Lock screen:** if the
/// device is locked, the overlay asks to unlock first and shows nothing
/// else; no request runs, nothing is shown or spoken until the device is
/// unlocked (see ADR 0006).
class AssistantOverlayScreen extends ConsumerStatefulWidget {
  /// Creates the overlay.
  const AssistantOverlayScreen({super.key, this.autoStart = true});

  /// Whether the first trigger fires when the overlay opens.
  final bool autoStart;

  @override
  ConsumerState<AssistantOverlayScreen> createState() =>
      _AssistantOverlayState();
}

class _AssistantOverlayState extends ConsumerState<AssistantOverlayScreen> {
  late final AssistantTriggerSource _triggers;
  late final StreamSubscription<TriggerEvent> _sub;
  final _text = TextEditingController();
  // Locked until the platform says otherwise: nothing personal may flash
  // up on a locked device.
  bool _locked = true;
  bool _lockKnown = false;
  bool _typing = false;
  bool _closing = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _triggers = AssistantTriggerSource(
      ref.read(assistantPlatformProvider),
      clock: ref.read(clockProvider),
    );
    _sub = _triggers.triggers.listen((e) => unawaited(_onTrigger(e)));
    // Android leaves the overlay (home, screen off): the Dart close path
    // first, so nothing keeps listening or speaking.
    ref.read(assistantPlatformProvider).onCloseRequested = _close;
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    unawaited(_checkLock());
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _triggers.fire());
    }
  }

  void _onLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      unawaited(_voice.suspend());
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_sub.cancel());
    unawaited(_triggers.dispose());
    _text.dispose();
    super.dispose();
  }

  AssistantPlatform get _platform => ref.read(assistantPlatformProvider);
  VoiceController get _voice => ref.read(voiceControllerProvider.notifier);
  AgentController get _agent => ref.read(agentControllerProvider.notifier);

  Future<bool> _checkLock() async {
    final locked = await _platform.isLocked();
    if (mounted) {
      setState(() {
        _locked = locked;
        _lockKnown = true;
      });
    }
    return locked;
  }

  Future<void> _onTrigger(TriggerEvent e) async {
    if (await _checkLock()) {
      if (!await _platform.requestUnlock() || !mounted) return;
      setState(() => _locked = false);
    }
    if (!mounted) return;
    setState(() => _typing = false);
    final voice = ref.read(voiceControllerProvider);
    if (voice.active) await _voice.cancel();
    if (ref.read(agentControllerProvider).running) return;
    await _voice.start(e.source, prepare: _microphoneAccess);
  }

  /// Microphone permission with explanation (WP17); not in the demo.
  Future<bool> _microphoneAccess() async {
    if (ref.read(demoModeProvider)) return true;
    return ensureMicrophoneAccess(context, ref.read(microphoneProvider));
  }

  Future<void> _unlock() async {
    if (await _platform.requestUnlock() && mounted) {
      setState(() => _locked = false);
      _triggers.fire();
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    await _voice.suspend();
    _agent.cancel();
    await _platform.finish();
  }

  void _toggleKeyboard() {
    if (ref.read(voiceControllerProvider).active) unawaited(_voice.cancel());
    setState(() => _typing = !_typing);
  }

  void _send(String text) {
    if (text.trim().isEmpty || ref.read(agentControllerProvider).running) {
      return;
    }
    _text.clear();
    setState(() => _typing = false);
    unawaited(_agent.send(text));
  }

  @override
  Widget build(BuildContext context) {
    final conversation = ref.watch(agentControllerProvider);
    final voice = ref.watch(voiceControllerProvider);
    final config = ref.watch(providerConfigProvider).value;
    final target = config?.targetFor(conversation.activeProfileId);
    final available = ref.watch(voiceReadyProvider);
    final mic = _locked
        ? MicState.disabled
        : micStateFor(
            voice,
            available: available,
            running: conversation.running,
          );
    final sheet = OverlaySheet(
      providerName: target == null ? '' : config!.nameOf(target.profileId),
      privacy: target?.privacy ?? PrivacyLevel.standard,
      checkStatus: conversation.verification?.checkStatus,
      exchange: _locked
          ? const OverlayExchange()
          : OverlayExchange.of(conversation.entries),
      listening: voice.listening,
      mic: mic,
      levels: voice.levels,
      locked: _locked,
      onUnlock: _lockKnown ? () => unawaited(_unlock()) : null,
      status: _locked
          ? null
          : voice.error ??
                voice.hint ??
                (available ? null : voiceUnavailableHint),
      question: _locked ? null : conversation.pending,
      onAnswer: (yes) => _agent.answer(approved: yes),
      hint: voice.active ? ConfirmationHint.voice : ConfirmationHint.tap,
      onMic: () {
        if (voice.active) {
          unawaited(_voice.cancel());
        } else if (conversation.running) {
          _agent.cancel();
        } else {
          unawaited(
            _voice.start(TriggerKind.assistant, prepare: _microphoneAccess),
          );
        }
      },
      onClose: () => unawaited(_close()),
      onKeyboard: _toggleKeyboard,
      onUndo: (id) => unawaited(_agent.undo(id)),
      typing: _typing
          ? TextField(
              controller: _text,
              autofocus: true,
              style: WText.body,
              textInputAction: TextInputAction.send,
              onSubmitted: _send,
              decoration: const InputDecoration(
                hintText: 'Schreiben statt sprechen',
                semanticCounterText: '',
              ),
            )
          : null,
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: Material(
        type: MaterialType.transparency,
        // Keyboard (text input) pushes the sheet up.
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = math.min(
                WSize.overlaySheet,
                constraints.maxHeight * WSize.overlayMaxFraction,
              );
              return Column(
                children: [
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'Assistent schließen',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => unawaited(_close()),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: height,
                    child: OverlayPanel(child: sheet),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Background of the overlay sheet: `ink`, rounded top corners, padding
/// as in the design; keeps the content above the keyboard.
class OverlayPanel extends StatelessWidget {
  /// Creates the panel.
  const OverlayPanel({super.key, required this.child});

  /// Sheet content.
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: WColors.ink,
      borderRadius: BorderRadius.vertical(top: Radius.circular(WRadius.sheet)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          WSpace.screen,
          WSpace.m14,
          WSpace.screen,
          WSpace.xxl,
        ),
        child: child,
      ),
    ),
  );
}
