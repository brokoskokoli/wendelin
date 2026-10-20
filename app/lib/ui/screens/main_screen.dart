import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart'
    show PortException;

import '../../agent/agent_controller.dart';
import '../../agent/chat_entry.dart';
import '../../agent/conversation_state.dart';
import '../../agent/money.dart';
import '../../di/attestation_hub.dart';
import '../../di/attestation_providers.dart';
import '../../di/hint_term_providers.dart';
import '../../di/obsidian_index.dart';
import '../../di/profiles.dart';
import '../../di/provider_config.dart';
import '../../di/providers.dart';
import '../../di/routing.dart';
import '../../di/voice_providers.dart';
import '../../l10n/l10n.dart';
import '../../platform/channel_notifier.dart' show attestationLogTarget;
import '../../voice/conversation_offer.dart';
import '../../voice/voice_components.dart';
import '../../voice/voice_controller.dart';
import '../../voice/wake/wake_chat.dart';
import '../attestation/attestation_texts.dart';
import '../routes.dart';
import '../settings/attestation_log_detail.dart';
import '../settings/attestation_log_screen.dart';
import '../settings/settings_page.dart' show confirm;
import '../voice/microphone_access.dart';
import 'conversation_offer_card.dart';
import 'conversation_view.dart';
import 'main_composer.dart';
import 'main_confirmation.dart';
import 'main_parts.dart';
import 'private_banner.dart';
import 'quick_switch.dart';

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

class _MainScreenState extends ConsumerState<MainScreen> with RouteAware {
  PendingQuestion? _sheetFor;
  bool _micDeniedByAndroid = false;
  late final AppLifecycleListener _lifecycle;
  late final WakeChatSession _wakeChat;
  ModalRoute<void>? _observed;

  @override
  void dispose() {
    wakeRouteObserver.unsubscribe(this);
    _wakeChat.dispose();
    _lifecycle.dispose();
    super.dispose();
  }

  // Another route above the chat (settings, dialog, sheet): wake word hits
  // go to the overlay then (WP93).
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && route != _observed) {
      wakeRouteObserver.unsubscribe(this);
      _observed = route;
      wakeRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPush() => _wakeChat.setRouteCurrent(true);

  @override
  void didPopNext() => _wakeChat.setRouteCurrent(true);

  @override
  void didPushNext() => _wakeChat.setRouteCurrent(false);

  @override
  void initState() {
    super.initState();
    _wakeChat = WakeChatSession(
      container: ProviderScope.containerOf(context, listen: false),
      prepare: _microphoneAccess,
    );
    // In the background nothing listens, speaks or runs on unseen.
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _wakeChat.setResumed(state == AppLifecycleState.resumed);
        final voice = ref.read(voiceControllerProvider.notifier);
        if (state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused) {
          // Also frees the speech models after a while (B14).
          unawaited(voice.background());
        } else if (state == AppLifecycleState.resumed) {
          // The overlay (own engine) may have marked the question as due.
          ref.invalidate(voiceSettingsProvider);
          // Contacts may have changed or been allowed meanwhile.
          ref.invalidate(hintTermsProvider);
          voice.prewarm(onlyIfUsed: true);
          // Back from the Android settings: allowed there meanwhile?
          unawaited(_recheckMicrophone());
          unawaited(_openFromNotification());
        }
      },
    );
    // Visible: load Whisper now, so the first tap starts at once (B11);
    // only for people who use speech (base load).
    Future(() {
      if (!mounted) return;
      ref.read(voiceControllerProvider.notifier).prewarm(onlyIfUsed: true);
    });
    Future(() => unawaited(_openFromNotification()));
    if (widget.restoreSession) {
      unawaited(ref.read(agentControllerProvider.notifier).restore());
      // A TEE default provider is attested in the background (WP52).
      unawaited(
        Future(
          () => warmUpAttestation(
            config: ref.read(providerConfigProvider.future),
            network: ref.read(networkStatusProvider),
            hub: ref.read(attestationHubProvider),
          ),
        ),
      );
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

  void _openAttestation(AnswerAttestation a) {
    if (a.logId.isEmpty) return;
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => AttestationLogDetailScreen(logId: a.logId),
        ),
      ),
    );
  }

  /// The app was opened from the notification of a failed GPU check: shows
  /// the Prüfprotokoll.
  Future<void> _openFromNotification() async {
    final target = await ref
        .read(attestationNotifierProvider)
        .takeLaunchTarget();
    if (!mounted || target != attestationLogTarget) return;
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const AttestationLogScreen()),
      ),
    );
  }

  /// „Neu prüfen“ on a red answer: checks the provider that gave this answer
  /// (from its log entry), not the one that is active now.
  Future<void> _reattest(AnswerAttestation a, ConversationState c) async {
    final record = a.logId.isEmpty
        ? null
        : await ref.read(storageProvider).attestations.byLogId(a.logId);
    final profile = record?.profileId ?? c.activeProfileId;
    if (profile == null) return;
    await _controller.reattest(profile);
  }

  /// The GPU check before the request failed: nothing was sent. Asks
  /// whether to send once without the check.
  Future<void> _askGpuBlock(GpuBlock block) async {
    final name =
        ref.read(providerConfigProvider).value?.nameOf(block.profileId) ??
        block.profileId;
    final send = await confirm(
      context,
      title: block.noEvidence
          ? context.l10n.gpuNoEvidenceTitle
          : context.l10n.mainGpuCheckFailedTitle,
      message: block.noEvidence
          ? context.l10n.gpuNoEvidenceMessage(name)
          : context.l10n.mainGpuBlockMessage(
              name,
              gpuBlockReason(context.l10n, block.reason),
            ),
      yes: context.l10n.mainSendWithoutGpuCheck,
      no: context.l10n.cancel,
    );
    await _controller.resolveGpuBlock(sendWithout: send);
  }

  /// Long press on the provider chip (WP94): the chosen agent becomes the
  /// default and the chat starts empty, so no history goes to the new one.
  Future<void> _quickSwitch(ProviderConfig? config) async {
    final profiles = (await ref.read(profilesProvider.future)).profiles;
    if (!mounted || profiles.length < 2) return;
    final current = _activeTarget(
      config,
      ref.read(agentControllerProvider).activeProfileId,
    )?.profileId;
    final id = await showQuickSwitchSheet(
      context,
      profiles: profiles,
      currentId: current,
    );
    if (id == null || id == current || !mounted) return;
    if (ref.read(agentControllerProvider).running) return;
    // Speech output of the last answer ends before the switch.
    await ref.read(voiceControllerProvider.notifier).cancel();
    await ref.read(profilesProvider.notifier).setDefault(id);
    await _controller.newTopic();
  }

  AgentController get _controller => ref.read(agentControllerProvider.notifier);

  void _listenAgent() {
    ref.listen(
      agentControllerProvider.select((s) => s.pending),
      (previous, next) => _onPending(next),
    );
    ref.listen(agentControllerProvider.select((s) => s.gpuBlock), (
      previous,
      next,
    ) {
      if (next != null) unawaited(_askGpuBlock(next));
    });
  }

  @override
  Widget build(BuildContext context) {
    _listenAgent();
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
    final profileCount =
        ref.watch(profilesProvider).value?.profiles.length ?? 0;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MainHeader(
            onSettings: () =>
                Navigator.of(context).pushNamed(AppRoutes.settings),
            onStation: ref.watch(platformPortsProvider).station == null
                ? null
                : () => unawaited(_startStation()),
            onNewConversation:
                conversation.entries.any((e) => e is! SessionStartEntry)
                ? () => unawaited(_controller.newTopic())
                : null,
            newConversationEnabled: !conversation.running,
          ),
          MainChips(
            onQuickSwitch: conversation.running || profileCount < 2
                ? null
                : () => unawaited(_quickSwitch(providers)),
            providerName: active == null
                ? null
                : providerLabel(
                    providers!.nameOf(active.profileId),
                    conversation.activeRule,
                  ),
            privacy: active?.privacy,
            costLabel: context.l10n.mainCostToday(
              formatUsdFor(context.l10n, cost),
            ),
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
              onAttestationTap: _openAttestation,
              onReattest: (a) => unawaited(_reattest(a, conversation)),
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
        error: context.l10n.mainProviderProfileUnusable('${config.error}'),
      );
    } else if (config.hasValue && providers == null) {
      return ProviderSetupCard(
        onSetup: _openProviderSetup,
        onDemo: () => ref.read(demoModeProvider.notifier).set(enabled: true),
      );
    } else if (ref.watch(conversationOfferProvider)) {
      return ConversationOfferCard(
        onAnswer: (yes) => unawaited(
          ref.read(conversationOfferProvider.notifier).answer(yes: yes),
        ),
      );
    } else if (notice != null) {
      return PrivateRuleNoticeCard(
        text: privateRuleNoticeText(context.l10n, notice),
        onOpen: () {
          unawaited(dismissPrivateRuleNotice(ref));
          unawaited(Navigator.of(context).pushNamed(AppRoutes.routing));
        },
        onDismiss: () => unawaited(dismissPrivateRuleNotice(ref)),
      );
    }
    return null;
  }

  /// Starts the station mode; a failure (e.g. no activity available) is shown.
  Future<void> _startStation() async {
    try {
      await ref.read(platformPortsProvider).station!.start();
    } on PortException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
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
