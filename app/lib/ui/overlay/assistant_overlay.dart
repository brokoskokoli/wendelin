import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../agent/agent_controller.dart';
import '../../agent/conversation_state.dart';
import '../../di/provider_config.dart';
import '../../di/providers.dart';
import '../../di/voice_providers.dart';
import '../../di/wake_settings.dart';
import '../../platform/assistant_platform.dart';
import '../../voice/voice_components.dart';
import '../../voice/voice_controller.dart';
import '../../voice/voice_log.dart';
import '../design/design.dart';
import '../screens/confirmation_sheet.dart';
import '../screens/private_banner.dart';
import '../voice/microphone_access.dart';
import 'overlay_frame.dart';
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
/// device is locked, the overlay still listens but shows nothing; only a
/// local flashlight command runs (no model, K16, WP53), anything else gets
/// „Bitte entsperre das Telefon“, then the unlock prompt (see ADR 0006).
class AssistantOverlayScreen extends ConsumerStatefulWidget {
  /// Creates the overlay.
  const AssistantOverlayScreen({super.key, this.autoStart = true});

  /// Whether the first trigger fires when the overlay opens.
  final bool autoStart;

  /// How long „Abgebrochen.“ stays before the overlay closes.
  @visibleForTesting
  static Duration stopCloseDelay = const Duration(milliseconds: 1200);

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
  // After a spoken „Stopp“ (B5): entries before this index belong to the
  // exchange that was cancelled and are not shown; the overlay closes
  // after [stopCloseDelay] if the setting says so.
  int _hideBefore = 0;
  Timer? _closeTimer;
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
      // Load the tone setting and the tone itself before the first hit.
      ref
        ..read(wakeToneProvider)
        ..read(wakeConfirmToneProvider);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_fireFirst()),
      );
    }
  }

  // The first trigger: the wake word service leaves its hit with the
  // platform before it opens the overlay (WP50).
  Future<void> _fireFirst() async {
    // Every invocation of the assistant starts a new conversation (WP67).
    _agent.beginFreshConversation();
    final preRoll = await _platform.takeWakeHandoff();
    if (preRoll != null) {
      voiceLog('wake-handoff', {'ms': samplesToDuration(preRoll.length)});
    }
    if (mounted) _triggers.fire(preRoll: preRoll);
  }

  void _onLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      unawaited(_voice.suspend());
    }
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
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
      // Unlocked and visible: load Whisper (never before unlocking, B11).
      if (!locked) _voice.prewarm();
    }
    return locked;
  }

  /// Every trigger (power button, wake word) takes this path. Locked: it listens without showing anything (Whisper, up to
  /// ~375 MB, is loaded for that and freed when the overlay closes); the
  /// voice pipeline only lets local flashlight commands through
  /// ([LockGateAgentRun], K16), the rest gets the fixed sentence „Bitte
  /// entsperre das Telefon“, the utterance is dropped, and the unlock
  /// button shows. Nothing asks for the unlock by itself.
  Future<void> _onTrigger(TriggerEvent e) async {
    final locked = await _checkLock();
    if (!mounted) return;
    ref.read(lockedModeProvider.notifier).set(locked);
    _closeTimer?.cancel();
    setState(() => _typing = false);
    final voice = ref.read(voiceControllerProvider);
    if (voice.active) await _voice.cancel();
    if (ref.read(agentControllerProvider).running) return;
    // Wake word hit: a short tone (setting „Bestätigungston“), not awaited.
    // Setting and tone are loaded in initState; the tone is cut from the
    // recording (the microphone hears the speaker otherwise).
    var tone = false;
    if (e.source == TriggerKind.wakeWord) {
      tone =
          ref.read(wakeToneProvider).value ??
          await ref.read(wakeToneProvider.future);
    }
    if (!mounted) return;
    if (tone) unawaited(ref.read(wakeConfirmToneProvider)());
    await _voice.start(
      e.source,
      preRoll: e.preRoll,
      muteMicSamples: tone ? wakeToneMuteSamples : 0,
      // No permission dialog on the lock screen.
      prepare: locked ? _microphoneGranted : _microphoneAccess,
    );
  }

  Future<bool> _microphoneGranted() async =>
      ref.read(demoModeProvider) ||
      await ref.read(microphoneProvider).hasPermission(request: false);

  /// Microphone permission with explanation (WP17); not in the demo.
  Future<bool> _microphoneAccess() async {
    if (ref.read(demoModeProvider)) return true;
    return ensureMicrophoneAccess(context, ref.read(microphoneProvider));
  }

  void _onStop() {
    final entries = ref.read(agentControllerProvider).entries;
    setState(() => _hideBefore = entries.length);
    final closes =
        ref.read(voiceSettingsProvider).value?.stopClosesOverlay ?? true;
    _closeTimer?.cancel();
    if (closes) {
      _closeTimer = Timer(AssistantOverlayScreen.stopCloseDelay, () {
        if (mounted) unawaited(_close());
      });
    }
  }

  // A request was refused while locked: after the spoken hint the system
  // unlock opens (the utterance itself is dropped).
  Future<void> _offerUnlock() async {
    await _voice.whenIdle;
    if (mounted && _locked && !_closing) await _unlock();
  }

  Future<void> _unlock() async {
    if (await _platform.requestUnlock() && mounted) {
      setState(() => _locked = false);
      ref.read(lockedModeProvider.notifier).set(false);
      _triggers.fire();
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    await _voice.suspend();
    ref.read(lockedModeProvider.notifier).set(false);
    _agent.cancel();
    // The engine ends with the overlay: free an own Whisper model now, so
    // none stays behind in the process (B14).
    try {
      await _voice
          .releaseModels(reason: 'overlay-close')
          .timeout(const Duration(milliseconds: 600));
    } on TimeoutException {
      // Finish anyway; the release continues in the background.
    }
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

  Widget _sheet(
    ConversationState conversation,
    VoiceUiState voice, {
    required bool available,
    required MicState mic,
    required ProviderTarget? target,
    required ProviderConfig? config,
  }) => OverlaySheet(
    providerName: target == null
        ? ''
        : providerLabel(
            config!.nameOf(target.profileId),
            conversation.activeRule,
          ),
    privacy: target?.privacy ?? PrivacyLevel.standard,
    privateSince: _locked ? null : conversation.privateSince,
    privateByRequest: conversation.privateByRequest,
    onNewConversation: conversation.running
        ? null
        : () => unawaited(_agent.newTopic()),
    checkStatus: conversation.verification?.checkStatus,
    exchange: _locked
        ? const OverlayExchange()
        : OverlayExchange.of(
            conversation.entries.sublist(
              _hideBefore > conversation.entries.length ? 0 : _hideBefore,
            ),
          ),
    listening: voice.listening,
    preparing: voice.preparing,
    mic: mic,
    levels: voice.levels,
    conversationMode:
        ref.watch(voiceSettingsProvider).value?.conversationMode ?? false,
    followUpUntil: voice.followUpUntil,
    now: ref.read(clockProvider).now,
    locked: _locked,
    onUnlock: _lockKnown ? () => unawaited(_unlock()) : null,
    status: _locked
        ? null
        : voice.error ??
              voice.hint ??
              (available ? null : voiceUnavailableHint),
    question: _locked ? null : conversation.pending,
    onAnswer: (yes) => _agent.answer(approved: yes),
    hint: voice.answersByVoice ? ConfirmationHint.voice : ConfirmationHint.tap,
    onMic: () => _onMic(voice, conversation),
    onClose: () => unawaited(_close()),
    onKeyboard: _toggleKeyboard,
    onUndo: (id) => unawaited(_voice.undo(id)),
    typing: _typing ? _typingField() : null,
  );

  void _onMic(VoiceUiState voice, ConversationState conversation) {
    if (voice.active) {
      unawaited(_voice.cancel());
    } else if (conversation.running) {
      _agent.cancel();
    } else {
      unawaited(
        _voice.start(TriggerKind.assistant, prepare: _microphoneAccess),
      );
    }
  }

  Widget _typingField() => TextField(
    controller: _text,
    autofocus: true,
    style: WText.body,
    textInputAction: TextInputAction.send,
    onSubmitted: _send,
    decoration: const InputDecoration(
      hintText: 'Schreiben statt sprechen',
      semanticCounterText: '',
    ),
  );

  @override
  Widget build(BuildContext context) {
    ref
      ..listen(voiceControllerProvider.select((v) => v.stopCount), (_, _) {
        _onStop();
      })
      ..listen(lockedRefusalsProvider, (_, _) => unawaited(_offerUnlock()));
    final conversation = ref.watch(agentControllerProvider);
    final voice = ref.watch(voiceControllerProvider);
    final config = ref.watch(providerConfigProvider).value;
    final target = config?.targetFor(conversation.activeProfileId);
    final available = ref.watch(voiceReadyProvider);
    final mic = _locked && !voice.active
        ? MicState.disabled
        : micStateFor(
            voice,
            available: available,
            running: conversation.running,
          );
    final sheet = _sheet(
      conversation,
      voice,
      available: available,
      mic: mic,
      target: target,
      config: config,
    );
    return OverlayFrame(onClose: () => unawaited(_close()), child: sheet);
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
