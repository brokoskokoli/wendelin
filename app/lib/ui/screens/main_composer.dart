import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/agent_controller.dart';
import '../../agent/conversation_state.dart';
import '../../di/providers.dart';
import '../../di/voice_providers.dart';
import '../../l10n/l10n.dart';
import '../../voice/voice_components.dart';
import '../../voice/voice_controller.dart';
import '../design/design.dart';
import '../voice/microphone_access.dart';
import 'main_parts.dart';
import 'private_banner.dart';

/// Text field and microphone of the main screen: sends text, taps the
/// microphone (start, cancel listening, cancel the running request) and
/// shows the microphone notice when Android denied access.
class MainComposer extends ConsumerWidget {
  /// Creates the composer.
  const MainComposer({
    super.key,
    required this.conversation,
    required this.voice,
    required this.mic,
    required this.micDeniedByAndroid,
    required this.onAllowMicrophone,
    required this.microphoneAccess,
  });

  /// The conversation (running state).
  final ConversationState conversation;

  /// The voice state.
  final VoiceUiState voice;

  /// State of the microphone button.
  final MicState mic;

  /// Android denied the permission (notice offers the settings).
  final bool micDeniedByAndroid;

  /// „Erlauben“ on the notice.
  final VoidCallback onAllowMicrophone;

  /// Asks for the microphone permission before listening.
  final Future<bool> Function() microphoneAccess;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SafeArea(
    top: false,
    child: Composer(
      running: conversation.running,
      mic: mic,
      hearing: ref.watch(bargeListeningProvider),
      levels: voice.levels,
      followUpUntil: voice.followUpUntil,
      now: ref.read(clockProvider).now,
      micHint: context.l10n.voiceUnavailableHint,
      status: switch (voice.error ?? voice.hint) {
        final String s => voiceStatusText(context.l10n, s),
        _ => null,
      },
      notice: voice.error == microphoneDeniedHint
          ? MicrophoneNotice(
              deniedByAndroid: micDeniedByAndroid,
              onAllow: onAllowMicrophone,
              onOpenSettings: () =>
                  unawaited(ref.read(appSettingsOpenerProvider)()),
            )
          : null,
      onMic: () => _onMic(ref),
      onSend: (text) {
        if (conversation.running || text.trim().isEmpty) return false;
        unawaited(ref.read(agentControllerProvider.notifier).send(text));
        return true;
      },
    ),
  );

  void _onMic(WidgetRef ref) {
    final voiceController = ref.read(voiceControllerProvider.notifier);
    if (voice.active) {
      unawaited(voiceController.cancel());
    } else if (conversation.running) {
      ref.read(agentControllerProvider.notifier).cancel();
    } else {
      unawaited(voiceController.tap(prepare: microphoneAccess));
    }
  }
}

/// Banner „Unterhaltung privat“ above the conversation.
class MainPrivateBanner extends StatelessWidget {
  /// Creates the banner.
  const MainPrivateBanner({
    super.key,
    required this.since,
    required this.byRequest,
    required this.onNewConversation,
  });

  /// Since when the conversation is private.
  final DateTime since;

  /// The state comes from a „privat“ request.
  final bool byRequest;

  /// Starts a new conversation; `null` while a request runs.
  final VoidCallback? onNewConversation;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      WSpace.screen,
      0,
      WSpace.screen,
      WSpace.m,
    ),
    child: PrivateConversationBanner(
      since: since,
      byRequest: byRequest,
      onNewConversation: onNewConversation,
    ),
  );
}
