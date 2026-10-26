import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../di/agent_providers.dart';
import 'agent_controller.dart';

/// `ref.read` of a widget or `container.read`.
typedef Reader = T Function<T>(ProviderListenable<T> provider);

/// Session end by absence (WP157 part B, ADR 0023): the app chat ends when
/// the window was out of sight for a minute.
///
/// The window is visible again. After a minute or more out of sight the
/// session has ended: the chat is empty again, the history keeps it. A
/// running request keeps its view.
Future<void> returnedToScreen(Reader read) async {
  if (await read(sessionManagerProvider).returnedToScreen()) {
    read(agentControllerProvider.notifier).beginFreshConversation();
  }
}

/// Restores the chat after an app start, unless the app was away for a
/// minute or more (also across a kill in the background): then it starts
/// empty.
Future<void> restoreChat(Reader read) async {
  if (!await read(sessionManagerProvider).returnedToScreen()) {
    await read(agentControllerProvider.notifier).restore();
  }
}

/// Feeds the window visibility to the session.
void trackAbsence(Reader read, AppLifecycleState state) {
  if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
    read(sessionManagerProvider).leftScreen();
  } else if (state == AppLifecycleState.resumed) {
    returnedToScreen(read);
  }
}
