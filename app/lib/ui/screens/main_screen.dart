import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_agent/wendelin_agent.dart';

import '../../agent/agent_controller.dart';
import '../../agent/chat_entry.dart';
import '../../agent/conversation_state.dart';
import '../../agent/money.dart';
import '../../di/obsidian_index.dart';
import '../../di/provider_config.dart';
import '../../di/providers.dart';
import '../../di/routing.dart';
import '../../di/voice_providers.dart';
import '../../voice/voice_components.dart';
import '../../voice/voice_controller.dart';
import '../routes.dart';
import '../voice/microphone_access.dart';
import 'conversation_view.dart';
import 'main_composer.dart';
import 'main_confirmation.dart';
import 'main_parts.dart';
import 'private_banner.dart';

/// Main screen (docs/design/screens/hauptbildschirm): head, provider and
/// cost chips, conversation, text field and microphone. Confirmations open
/// as bottom sheet.
class MainScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const MainScreen({super.key, this.restoreSession = true});

  /// Whether the open session is restored on start (off for goldens).
  final bool restoreSession;

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  PendingQuestion? _sheetFor;
  bool _micDeniedByAndroid = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // In the background nothing listens, speaks or runs on unseen.
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        final voice = ref.read(voiceControllerProvider.notifier);
        if (state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused) {
          // Also frees the speech models after a while (B14).
          unawaited(voice.background());
        } else if (state == AppLifecycleState.resumed) {
          voice.prewarm(onlyIfUsed: true);
          // Back from the Android settings: allowed there meanwhile?
          unawaited(_recheckMicrophone());
        }
      },
    );
    // Visible: load Whisper now, so the first tap starts at once (B11);
    // only for people who use speech (base load).
    Future(() {
      if (!mounted) return;
      ref.read(voiceControllerProvider.notifier).prewarm(onlyIfUsed: true);
    });
    if (widget.restoreSession) {
      unawaited(ref.read(agentControllerProvider.notifier).restore());
      // A large vault needs several index runs: continue in the background.
      if (ref.read(enabledIntegrationsProvider).contains('obsidian') ||
          ref.read(demoModeProvider)) {
        // After the first build: sync() updates its provider right away,
        // which Riverpod forbids while widgets build (e.g. right after the
        // onboarding).
        unawaited(
          Future(() async {
            if (mounted) await ref.read(obsidianIndexProvider.notifier).sync();
          }),
        );
      }
    }
  }

  AgentController get _controller => ref.read(agentControllerProvider.notifier);

  @override
  Widget build(BuildContext context) {
    ref.listen(
      agentControllerProvider.select((s) => s.pending),
      (previous, next) => _onPending(next),
    );
    final conversation = ref.watch(agentControllerProvider);
    final config = ref.watch(providerConfigProvider);
    final cost = ref.watch(todayCostProvider).value ?? 0;
    final providers = config.value;
    final voice = ref.watch(voiceControllerProvider);
    final mic = micStateFor(
      voice,
      available: ref.watch(voiceReadyProvider),
      running: conversation.running,
    );
    final active = _activeTarget(providers, conversation.activeProfileId);

    final setupHint = _setupHint(config, providers);

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MainHeader(
            onSettings: () =>
                Navigator.of(context).pushNamed(AppRoutes.settings),
            onNewConversation:
                conversation.entries.any((e) => e is! SessionStartEntry)
                ? () => unawaited(_controller.newTopic())
                : null,
            newConversationEnabled: !conversation.running,
          ),
          MainChips(
            providerName: active == null
                ? null
                : providerLabel(
                    providers!.nameOf(active.profileId),
                    conversation.activeRule,
                  ),
            privacy: active?.privacy,
            costLabel: 'heute ${formatUsd(cost)}',
          ),
          if (conversation.privateSince case final since?)
            MainPrivateBanner(
              since: since,
              byRequest: conversation.privateByRequest,
              onNewConversation: conversation.running
                  ? null
                  : () => unawaited(_controller.newTopic()),
            ),
          Expanded(
            child: ConversationView(
              entries: conversation.entries,
              now: ref.watch(clockProvider).now(),
              showThinking: ref.watch(showThinkingProvider),
              onUndo: (id) => unawaited(_undo(id)),
              header: setupHint,
            ),
          ),
          MainComposer(
            conversation: conversation,
            voice: voice,
            mic: mic,
            micDeniedByAndroid: _micDeniedByAndroid,
            onAllowMicrophone: () => unawaited(_allowMicrophone()),
            microphoneAccess: _microphoneAccess,
          ),
        ],
      ),
    );
  }

  Widget? _setupHint(
    AsyncValue<ProviderConfig?> config,
    ProviderConfig? providers,
  ) {
    final notice = ref.watch(privateRuleNoticeProvider).value;
    if (config.hasError) {
      return ProviderSetupCard(
        onSetup: _openProviderSetup,
        error:
            'Das Provider-Profil lässt sich nicht verwenden: '
            '${config.error}',
      );
    } else if (config.hasValue && providers == null) {
      return ProviderSetupCard(
        onSetup: _openProviderSetup,
        onDemo: () => ref.read(demoModeProvider.notifier).set(enabled: true),
      );
    } else if (notice != null) {
      return PrivateRuleNoticeCard(
        text: privateRuleNoticeText(notice),
        onOpen: () {
          unawaited(dismissPrivateRuleNotice(ref));
          unawaited(Navigator.of(context).pushNamed(AppRoutes.routing));
        },
        onDismiss: () => unawaited(dismissPrivateRuleNotice(ref)),
      );
    }
    return null;
  }

  /// Undo: a spoken answer stops, „Zurückgenommen.“ is shown (snackbar and
  /// line in the conversation) and spoken if the request came by voice.
  Future<void> _undo(String id) async {
    final text = await ref.read(voiceControllerProvider.notifier).undo(id);
    if (text == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Microphone permission with explanation (WP17); not in the demo.
  Future<bool> _microphoneAccess() async {
    if (ref.read(demoModeProvider)) return true;
    final access = await requestMicrophoneAccess(
      context,
      ref.read(microphoneProvider),
    );
    if (mounted) {
      setState(() => _micDeniedByAndroid = access == MicrophoneAccess.denied);
    }
    return access == MicrophoneAccess.granted;
  }

  /// „Erlauben“ on the notice: the explanation was read, Android asks.
  Future<void> _allowMicrophone() async {
    final granted = await ref.read(microphoneProvider).hasPermission();
    if (!mounted) return;
    if (granted) {
      ref.read(voiceControllerProvider.notifier).clearMessages();
    } else {
      setState(() => _micDeniedByAndroid = true);
    }
  }

  /// Clears the notice once the microphone is allowed (Android settings).
  Future<void> _recheckMicrophone() async {
    if (ref.read(voiceControllerProvider).error != microphoneDeniedHint) {
      return;
    }
    final granted = await ref
        .read(microphoneProvider)
        .hasPermission(request: false);
    if (granted && mounted) {
      ref.read(voiceControllerProvider.notifier).clearMessages();
      setState(() => _micDeniedByAndroid = false);
    }
  }

  void _openProviderSetup() =>
      Navigator.of(context).pushNamed(AppRoutes.providerSetup);

  static ProviderTarget? _activeTarget(ProviderConfig? config, String? id) =>
      config?.targetFor(id);

  void _onPending(PendingQuestion? next) {
    if (next == null) {
      // Answered elsewhere or the run ended: close an open sheet.
      if (_sheetFor != null) Navigator.of(context).pop();
      return;
    }
    if (!identical(next, _sheetFor)) unawaited(_showSheet(next));
  }

  Future<void> _showSheet(PendingQuestion question) async {
    if (_sheetFor != null) Navigator.of(context).pop();
    _sheetFor = question;
    final approved = await showQuestionSheet(context, ref, question);
    if (identical(_sheetFor, question)) _sheetFor = null;
    if (!mounted) return;
    // Only answer the question this sheet was opened for; a dismissed sheet
    // counts as „no“.
    if (identical(ref.read(agentControllerProvider).pending, question)) {
      _controller.answer(approved: approved ?? false);
    }
  }
}
