import 'package:flutter/widgets.dart';

import '../routes.dart';
import 'assistant_screen.dart';
import 'attestation_log_screen.dart';
import 'costs_screen.dart';
import 'integrations_screen.dart';
import 'memory_screen.dart';
import 'privacy_screen.dart';
import 'provider_setup_screen.dart';
import 'providers_screen.dart';
import 'routing/routing_screen.dart';
import 'settings_screen.dart';
import 'voice_screen.dart';
import 'wake/wake_word_screen.dart';

/// Routes of the general settings pages (overview, providers, routing,
/// integrations list, memory, privacy, costs, assistant, voice).
Map<String, WidgetBuilder> generalRoutes() => {
  AppRoutes.settings: (_) => const SettingsScreen(),
  AppRoutes.providerSetup: (_) => const ProviderSetupScreen(),
  AppRoutes.providers: (_) => const ProvidersScreen(),
  AppRoutes.integrations: (_) => const IntegrationsScreen(),
  AppRoutes.routing: (_) => const RoutingScreen(),
  AppRoutes.memory: (_) => const MemoryScreen(),
  AppRoutes.privacy: (_) => const PrivacyScreen(),
  AppRoutes.attestationLog: (_) => const AttestationLogScreen(),
  AppRoutes.costs: (_) => const CostsScreen(),
  AppRoutes.assistant: (_) => const AssistantScreen(),
  AppRoutes.voice: (_) => const VoiceScreen(),
  AppRoutes.wakeWord: (_) => const WakeWordScreen(),
};
