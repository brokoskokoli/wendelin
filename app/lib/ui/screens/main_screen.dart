import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../../agent/agent_controller.dart';
import '../../agent/conversation_state.dart';
import '../../agent/money.dart';
import '../../di/provider_config.dart';
import '../../di/providers.dart';
import '../routes.dart';
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

  @override
  void initState() {
    super.initState();
    if (widget.restoreSession) {
      unawaited(ref.read(agentControllerProvider.notifier).restore());
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
              onCancel: _controller.cancel,
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

  void _openProviderSetup() =>
      Navigator.of(context).pushNamed(AppRoutes.providerSetup);

  static ProviderTarget? _activeTarget(ProviderConfig? config, String? id) {
    if (config == null) return null;
    for (final t in [config.primary, ...config.chain]) {
      if (t.profileId == id) return t;
    }
    return config.primary;
  }

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
      builder: (_) => ConfirmationSheet(
        question: question,
        providerName: active == null ? '' : config!.nameOf(active.profileId),
        privacy: active?.privacy ?? PrivacyLevel.standard,
        toolRisk: question is ToolQuestion
            ? _riskOf(question.event.call.name)
            : RiskLevel.external,
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

  /// Level shown in the sheet. Until `ConfirmationRequired` carries the
  /// level (planned core follow-up), it is derived from the policy: every
  /// call the policy asks about is shown as `external` (needs confirmation),
  /// also a `write` tool the user made stricter.
  RiskLevel _riskOf(String toolName) {
    for (final integration in ref.read(integrationsProvider).values) {
      for (final tool in integration.tools) {
        if (tool.name != toolName) continue;
        final session = ref.read(sessionManagerProvider).currentId ?? '';
        final decision = ref.read(riskPolicyProvider).decide(tool, session);
        return decision.action == PolicyAction.confirm
            ? RiskLevel.external
            : tool.risk;
      }
    }
    return RiskLevel.external;
  }
}
