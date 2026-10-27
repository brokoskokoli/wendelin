import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../agent/agent_controller.dart';
import '../../agent/conversation_state.dart';
import '../../di/attestation_hub.dart';
import '../../di/attestation_providers.dart';
import '../../di/preferences.dart';
import '../../di/provider_config.dart';
import '../../di/providers.dart';
import '../../di/routing.dart';
import '../../di/voice_providers.dart';
import '../../di/wake_settings.dart';
import '../../l10n/l10n.dart';
import '../../platform/assistant_platform.dart';
import '../../voice/voice_components.dart';
import '../../voice/voice_controller.dart';
import '../../voice/voice_log.dart';
import '../../voice/wake/wake_pre_roll.dart';
import '../design/design.dart';
import '../screens/confirmation_sheet.dart';
import '../screens/private_banner.dart';
import '../voice/microphone_access.dart';
import 'overlay_frame.dart';
import 'overlay_sheet.dart';
import 'overlay_teardown.dart';
import 'unlock_window.dart';

/// Root widget of the assistant overlay (Dart entrypoint `assistantMain`,
/// started by `AssistantActivity` with a transparent window).
class AssistantOverlayApp extends ConsumerWidget {
  /// Creates the overlay app.
  const AssistantOverlayApp({super.key, this.autoStart = true});

  /// Whether the overlay starts listening right away (off for goldens).
  final bool autoStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    title: 'Wendelin',
    locale: uiLocaleFor(ref.watch(uiLanguageProvider)),
    localizationsDelegates: wendelinLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    localeListResolutionCallback: (l, s) => resolveUiLocale(l, s),
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

  /// Frees the native rest of the engine when the overlay closes (WP145).
  /// Tests keep their container alive and replace it.
  @visibleForTesting
  static Future<void> Function(ProviderContainer, AssistantPlatform)
  tearDownEngine = defaultTearDown;

  /// The real teardown (the test setup replaces [tearDownEngine]).
  @visibleForTesting
  static Future<void> defaultTearDown(
    ProviderContainer container,
    AssistantPlatform platform,
  ) => tearDownOverlayEngine(container);

  // After the host is released: free an own Whisper model (B14), tear down,
  // then the host may destroy the engine (`finish` if it cannot hold it).
  static Future<void> _finishClose(
    ProviderContainer container,
    AssistantPlatform platform, {
    required bool released,
    required Future<void> models,
  }) async {
    try {
      await models.timeout(const Duration(milliseconds: 600));
    } on TimeoutException {
      // The release continues; the teardown waits for it.
    }
    await tearDownEngine(container, platform);
    await (released ? platform.teardownDone() : platform.finish());
  }

  /// How long „Abgebrochen.“ stays before the overlay closes.
  @visibleForTesting
  static Duration stopCloseDelay = const Duration(milliseconds: 1200);

  @override
  ConsumerState<AssistantOverlayScreen> createState() =>
      _AssistantOverlayState();
}

// Recognition, follow-up listening or an answer is under way.
bool _requestRunning(WidgetRef ref) =>
    ref.read(voiceControllerProvider).active ||
    ref.read(agentControllerProvider).running;

/// Takes the audio of the wake word hit and plays the tone (WP68).
Future<WakePreRoll?> _takeWake(WidgetRef ref, {required bool tone}) =>
    takeWakePreRoll(
      platform: ref.read(assistantPlatformProvider),
      tone: tone,
      playTone: ref.read(wakeConfirmToneProvider),
    );

// No permission dialog on the lock screen.
Future<bool> _microphoneGranted(WidgetRef ref) async =>
    ref.read(demoModeProvider) ||
    await ref.read(microphoneProvider).hasPermission(request: false);

/// Microphone permission with explanation (WP17); not in the demo.
Future<bool> _microphoneAccess(BuildContext context, WidgetRef ref) async {
  if (ref.read(demoModeProvider)) return true;
  return ensureMicrophoneAccess(context, ref.read(microphoneProvider));
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
  // The keyguard transition is not „leaving“ the overlay and not a tap
  // (WP114, K85): while the unlock runs and shortly after, lifecycle
  // changes, taps outside and the platform close request are ignored.
  late final UnlockWatch _unlockWatch;
  // The request refused while locked was dropped (unlock cancelled).
  bool _discardedNotice = false;
  // After a spoken „Stopp“ (B5): entries before this index belong to the
  // exchange that was cancelled and are not shown; the overlay closes
  // after [stopCloseDelay] if the setting says so.
  int _hideBefore = 0;
  Timer? _closeTimer;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _unlockWatch = UnlockWatch(ref.read(clockProvider));
    _triggers = AssistantTriggerSource(
      ref.read(assistantPlatformProvider),
      clock: ref.read(clockProvider),
    );
    _sub = _triggers.triggers.listen((e) => unawaited(_onTrigger(e)));
    // Android leaves the overlay (home, screen off): the Dart close path
    // first, so nothing keeps listening or speaking.
    ref.read(assistantPlatformProvider).onCloseRequested =
        _closeUnlessUnlocking;
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    unawaited(_checkLock());
    _warmUpAttestation();
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
  // platform before it opens the overlay (WP50). Only a look: the audio is
  // taken right before the microphone opens here (WP68), the service records
  // until then.
  Future<void> _fireFirst() async {
    if (_closing) return;
    _agent.beginFreshConversation(); // every invocation starts anew (WP67)
    final wake = await _platform.hasWakeHandoff();
    if (mounted && !_closing) _triggers.fire(wake: wake);
  }

  // Platform close request, tap outside the sheet or back: not while the
  // unlock settles.
  Future<void> _closeUnlessUnlocking() async {
    if (!_unlockWatch.window.active) await _close('platform');
  }

  void _onLifecycle(AppLifecycleState state) {
    if (_closing) return;
    if (state == AppLifecycleState.resumed) _unlockWatch.resumed();
    if (_unlockWatch.window.active) return;
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      unawaited(_voice.suspend());
    }
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _unlockWatch.dispose();
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
    // Unreadable state counts as locked (fail-closed, WP158).
    final locked = await _platform.isLocked().catchError((Object e) {
      voiceLog('lock-check-failed', {'error': errorCode(e)});
      return true;
    });
    if (mounted && !_closing) {
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
  /// A TEE default provider is checked and connected in the background
  /// while the user is still speaking (WP77): this engine has its own
  /// providers and the main app's warm-up does not reach it. A valid
  /// session is kept, the call is cheap then.
  void _warmUpAttestation() => scheduleMicrotask(() {
    if (!mounted || _closing) return;
    unawaited(
      warmUpAttestation(
        config: ref.read(providerConfigProvider.future),
        network: ref.read(networkStatusProvider),
        hub: ref.read(attestationHubProvider),
      ),
    );
  });

  Future<void> _onTrigger(TriggerEvent e) async {
    if (_closing) return;
    _warmUpAttestation();
    final locked = await _checkLock();
    if (!mounted || _closing) return;
    ref.read(lockedModeProvider.notifier).set(locked);
    _closeTimer?.cancel();
    setState(() {
      _typing = false;
      _discardedNotice = false;
    });
    final voice = ref.read(voiceControllerProvider);
    if (voice.active) await _voice.cancel(VoiceCancelReason.retrigger);
    if (_closing) return;
    if (ref.read(agentControllerProvider).running) {
      // Nobody takes the hit over: release the service microphone (WP68).
      if (e.source == TriggerKind.wakeWord) await _platform.takeWakeHandoff();
      return;
    }
    // Wake word hit: a short tone (setting „Bestätigungston“), not awaited.
    // Setting and tone are loaded in initState; the tone is cut from the
    // recording (the microphone hears the speaker otherwise).
    var tone = false;
    if (e.source == TriggerKind.wakeWord) {
      tone =
          ref.read(wakeToneProvider).value ??
          await ref.read(wakeToneProvider.future);
    }
    if (!mounted || _closing) return;
    var taken = false;
    final wake = e.source == TriggerKind.wakeWord;
    try {
      await _voice.start(
        e.source,
        takePreRoll: wake
            ? () {
                taken = true;
                return _takeWake(ref, tone: tone);
              }
            : null,
        prepare: locked
            ? () => _microphoneGranted(ref)
            : () => _microphoneAccess(context, ref),
      );
    } on Object catch (err) {
      // The service must not keep recording after a failed start (WP158).
      voiceLog('start-failed', {'reason': 'trigger', 'error': errorCode(err)});
      // A take that already succeeded (`keepOpen`) leaves the service
      // recording: end that handoff at once instead of waiting for the guard.
      if (taken) await _platform.finishWakeHandoff();
      taken = false;
    }
    // Not started (busy, refused): the service must not keep recording.
    if (wake && !taken && !_closing) await _platform.takeWakeHandoff();
  }

  void _onStop() {
    final entries = ref.read(agentControllerProvider).entries;
    setState(() => _hideBefore = entries.length);
    _closeTimer?.cancel();
    _closeTimer = Timer(AssistantOverlayScreen.stopCloseDelay, () {
      if (mounted) unawaited(_close('stop'));
    });
  }

  // A request was refused while locked: after the spoken hint the system
  // unlock opens (the utterance itself is dropped).
  Future<void> _offerUnlock() async {
    await _voice.whenIdle;
    if (mounted && _locked && !_closing) await _unlock();
  }

  Future<void> _unlock() async {
    // Only an open request blocks a new one (not the grace period).
    if (_unlockWatch.window.open) return;
    final ok = await _unlockWatch.run(
      _platform.requestUnlock,
      alive: () => mounted && !_closing,
      close: () => unawaited(_close('unlock-timeout')),
    );
    if (!mounted) return;
    final pending = ref.read(lockedPendingProvider);
    final request = ref.read(lockedPendingProvider.notifier).take();
    final text = request?.text;
    if (!ok) {
      // Cancelled: the request is gone, say so (fixed text).
      if (pending != null) setState(() => _discardedNotice = true);
      return;
    }
    setState(() {
      _locked = false;
      _discardedNotice = false;
    });
    ref.read(lockedModeProvider.notifier).set(false);
    ref.read(lockedExchangeProvider.notifier).clear();
    // Gone meanwhile (home, screen off): nothing listens or sends.
    if (!await _unlockWatch.visibleAfterUnlock(() => mounted)) {
      if (mounted) await _close('hidden');
      return;
    }
    _voice.prewarm();
    // The request from before goes on now, answered here and read aloud
    // (K85); without one, the overlay listens again.
    if (text != null) {
      // WP163 B: a remembered tool call runs once, armed for exactly this
      // request; the gate runs it instead of a model (it takes the arming
      // when the run starts). Speech not available: disarmed, and the
      // request goes on as a normal typed one.
      final armed = ref.read(lockedArmedCallProvider.notifier);
      if (request!.call != null) armed.arm(request);
      final spoken = !_closing && await _voice.answerText(text);
      if (!spoken) armed.clear();
      if (!spoken && mounted && !_closing) unawaited(_agent.send(text));
    } else if (!_closing && !_requestRunning(ref)) {
      _triggers.fire();
    }
  }

  Future<void> _close(String by) async {
    if (_closing) return;
    _closing = true;
    voiceLog('overlay-close', {'by': by});
    final container = ProviderScope.containerOf(context, listen: false);
    final platform = _platform;
    ref.read(lockedPendingProvider.notifier).clear();
    ref.read(lockedArmedCallProvider.notifier).clear();
    ref.read(lockedExchangeProvider.notifier).clear();
    // An open GPU block is dropped with the overlay (WP82).
    unawaited(_agent.resolveGpuBlock(sendWithout: false));
    // Stop first (host channels), then release the host (WP145).
    await _voice.suspend();
    ref.read(lockedModeProvider.notifier).set(false);
    _agent.cancel();
    final released = await platform.releaseHost();
    await AssistantOverlayScreen._finishClose(
      container,
      platform,
      released: released,
      models: _voice.releaseModels(reason: 'overlay-close'),
    );
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
    required bool hearing,
    required ProviderTarget? target,
    required ProviderConfig? config,
  }) => OverlaySheet(
    hearing: hearing,
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
        ? OverlayExchange(
            request: ref.watch(lockedExchangeProvider)?.request,
            answer: ref.watch(lockedExchangeProvider)?.answer,
          )
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
    lockedNotice: _discardedNotice ? context.l10n.overlayUnlockCancelled : null,
    status: _locked
        ? null
        : switch (voice.error ??
              voice.hint ??
              (available ? null : voiceUnavailableError)) {
            final String s => voiceStatusText(context.l10n, s),
            _ => null,
          },
    question: _locked ? null : conversation.pending,
    gpuBlock: conversation.gpuBlock,
    onGpuBlock: ({required sendWithout}) =>
        unawaited(_agent.resolveGpuBlock(sendWithout: sendWithout)),
    onAnswer: (yes) => _agent.answer(approved: yes),
    hint: voice.answersByVoice ? ConfirmationHint.voice : ConfirmationHint.tap,
    onMic: () => _onMic(voice, conversation),
    onClose: () => unawaited(_close('tap')),
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
        _voice.start(
          TriggerKind.assistant,
          prepare: () => _microphoneAccess(context, ref),
        ),
      );
    }
  }

  Widget _typingField() => TextField(
    controller: _text,
    autofocus: true,
    style: WText.body,
    textInputAction: TextInputAction.send,
    onSubmitted: _send,
    decoration: InputDecoration(
      hintText: context.l10n.mainTypeInstead,
      semanticCounterText: '',
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_closing) return const SizedBox.shrink();
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
      hearing: ref.watch(bargeListeningProvider),
      target: target,
      config: config,
    );
    return OverlayFrame(
      onClose: () => unawaited(_closeUnlessUnlocking()),
      child: sheet,
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
