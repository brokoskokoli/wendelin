import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../agent/agent_controller.dart';
import '../../agent/conversation_state.dart';
import '../../agent/money.dart';
import '../../di/obsidian_index.dart';
import '../../di/provider_config.dart';
import '../../di/providers.dart';
import '../../di/voice_providers.dart';
import '../../voice/voice_components.dart';
import '../../voice/voice_controller.dart';
import '../routes.dart';
import '../voice/microphone_access.dart';
import 'confirmation_sheet.dart';
import 'conversation_view.dart';
import 'main_parts.dart';

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
        if (state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused) {
          unawaited(ref.read(voiceControllerProvider.notifier).suspend());
        }
      },
    );
    if (widget.restoreSession) {
      unawaited(ref.read(agentControllerProvider.notifier).restore());
      // A large vault needs several index runs: continue in the background.
      if (ref.read(enabledIntegrationsProvider).contains('obsidian') ||
          ref.read(demoModeProvider)) {
        unawaited(ref.read(obsidianIndexProvider.notifier).sync());
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

    Widget? setupHint;
    if (config.hasError) {
      setupHint = ProviderSetupCard(
        onSetup: _openProviderSetup,
        error:
            'Das Provider-Profil lässt sich nicht verwenden: '
            '${config.error}',
      );
    } else if (config.hasValue && providers == null) {
      setupHint = ProviderSetupCard(
        onSetup: _openProviderSetup,
        onDemo: () => ref.read(demoModeProvider.notifier).set(enabled: true),
      );
    }

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MainHeader(
            onSettings: () =>
                Navigator.of(context).pushNamed(AppRoutes.settings),
          ),
          MainChips(
            providerName: active == null
                ? null
                : providers!.nameOf(active.profileId),
            privacy: active?.privacy,
            costLabel: 'heute ${formatUsd(cost)}',
          ),
          Expanded(
            child: ConversationView(
              entries: conversation.entries,
              now: ref.watch(clockProvider).now(),
              showThinking: ref.watch(showThinkingProvider),
              onUndo: (id) => unawaited(_controller.undo(id)),
              header: setupHint,
            ),
          ),
          SafeArea(
            top: false,
            child: Composer(
              running: conversation.running,
              mic: mic,
              micHint: voiceUnavailableHint,
              status: voice.error ?? voice.hint,
              onMic: () {
                if (voice.active) {
                  unawaited(
                    ref.read(voiceControllerProvider.notifier).cancel(),
                  );
                } else if (conversation.running) {
                  _controller.cancel();
                } else {
                  unawaited(
                    ref
                        .read(voiceControllerProvider.notifier)
                        .tap(prepare: _microphoneAccess),
                  );
                }
              },
              onSend: (text) {
                if (conversation.running || text.trim().isEmpty) return false;
                unawaited(_controller.send(text));
                return true;
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Microphone permission with explanation (WP17); not in the demo.
  Future<bool> _microphoneAccess() async {
    if (ref.read(demoModeProvider)) return true;
    return ensureMicrophoneAccess(context, ref.read(microphoneProvider));
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
    final config = ref.read(providerConfigProvider).value;
    final active = _activeTarget(
      config,
      ref.read(agentControllerProvider).activeProfileId,
    );
    final approved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => Consumer(
        builder: (context, ref, _) => ConfirmationSheet(
          question: question,
          providerName: active == null ? '' : config!.nameOf(active.profileId),
          privacy: active?.privacy ?? PrivacyLevel.standard,
          toolRisk: question is ToolQuestion
              ? question.event.risk
              : RiskLevel.external,
          // A voice request also takes a spoken „ja“/„nein“.
          hint: ref.watch(voiceControllerProvider.select((v) => v.active))
              ? ConfirmationHint.voice
              : ConfirmationHint.tap,
        ),
      ),
    );
    if (identical(_sheetFor, question)) _sheetFor = null;
    if (!mounted) return;
    // Only answer the question this sheet was opened for; a dismissed sheet
    // counts as „no“.
    if (identical(ref.read(agentControllerProvider).pending, question)) {
      _controller.answer(approved: approved ?? false);
    }
  }
}
