import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'ui/design/gallery.dart';
import 'ui/onboarding/onboarding_screen.dart';
import 'ui/routes.dart';
import 'ui/screens/main_screen.dart';
import 'ui/settings/assistant_screen.dart';
import 'ui/settings/bring_screen.dart';
import 'ui/settings/coming_soon_screen.dart';
import 'ui/settings/costs_screen.dart';
import 'ui/settings/http_tool_editor_screen.dart';
import 'ui/settings/http_tools_screen.dart';
import 'ui/settings/integrations_screen.dart';
import 'ui/settings/lists_screen.dart';
import 'ui/settings/memory_screen.dart';
import 'ui/settings/obsidian_screen.dart';
import 'ui/settings/privacy_screen.dart';
import 'ui/settings/provider_setup_screen.dart';
import 'ui/settings/providers_screen.dart';
import 'ui/settings/routing/routing_screen.dart';
import 'ui/settings/settings_screen.dart';
import 'ui/settings/voice_screen.dart';
import 'ui/settings/web_search_screen.dart';
import 'ui/theme/app_theme.dart';

/// Root widget (inside a `ProviderScope`). Until the onboarding is done it
/// shows the onboarding instead of [home].
class WendelinApp extends StatelessWidget {
  /// Creates the app.
  const WendelinApp({super.key, this.home = const MainScreen()});

  /// Start screen (tests may replace it).
  final Widget home;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Wendelin',
    debugShowCheckedModeBanner: false,
    theme: buildWendelinTheme(),
    home: StartGate(home: home),
    routes: {
      AppRoutes.settings: (_) => const SettingsScreen(),
      AppRoutes.providerSetup: (_) => const ProviderSetupScreen(),
      AppRoutes.providers: (_) => const ProvidersScreen(),
      AppRoutes.integrations: (_) => const IntegrationsScreen(),
      AppRoutes.routing: (_) => const RoutingScreen(),
      // Placeholder until WP27 (MCP).
      AppRoutes.mcpServers: (_) => const ComingSoonScreen(
        title: 'MCP-Server',
        what:
            'Server hinzufügen (Vorlage oder frei), Anmeldung, Status und '
            'Tool-Liste.',
      ),
      AppRoutes.httpTools: (_) => const HttpToolsScreen(),
      AppRoutes.httpToolNew: (_) => const HttpToolEditorScreen(),
      AppRoutes.bring: (_) => const BringScreen(),
      AppRoutes.lists: (_) => const ListsScreen(),
      AppRoutes.webSearch: (_) => const WebSearchScreen(),
      AppRoutes.memory: (_) => const MemoryScreen(),
      AppRoutes.privacy: (_) => const PrivacyScreen(),
      AppRoutes.costs: (_) => const CostsScreen(),
      AppRoutes.assistant: (_) => const AssistantScreen(),
      AppRoutes.voice: (_) => const VoiceScreen(),
      AppRoutes.obsidian: (_) => const ObsidianScreen(),
      if (kDebugMode) AppRoutes.gallery: (_) => const DesignGallery(),
    },
  );
}
