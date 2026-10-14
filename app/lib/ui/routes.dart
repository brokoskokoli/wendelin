import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'design/gallery.dart';
import 'settings/general_routes.dart';
import 'settings/integration_routes.dart';

/// The route table of the app: only puts the areas together.
Map<String, WidgetBuilder> buildAppRoutes() => {
  ...generalRoutes(),
  ...integrationRoutes(),
  if (kDebugMode) AppRoutes.gallery: (_) => const DesignGallery(),
};

/// Named routes of the app.
abstract final class AppRoutes {
  /// Main screen.
  static const home = '/';

  /// Settings overview.
  static const settings = '/settings';

  /// New provider profile (setup dialog).
  static const providerSetup = '/settings/provider';

  /// Provider profiles and the default.
  static const providers = '/settings/providers';

  /// Routing rules (WP26).
  static const routing = '/settings/routing';

  /// Integrations.
  static const integrations = '/settings/integrations';

  /// MCP servers (WP27).
  static const mcpServers = '/settings/mcp';

  /// Declarative HTTP tools (WP28).
  static const httpTools = '/settings/http-tools';

  /// Editor of a new HTTP tool (WP28).
  static const httpToolNew = '/settings/http-tools/new';

  /// Bring! login and state (WP28).
  static const bring = '/settings/bring';

  /// Lists (K6).
  static const lists = '/settings/lists';

  /// Web search service.
  static const webSearch = '/settings/web';

  /// Memory entries.
  static const memory = '/settings/memory';

  /// Privacy and logs.
  static const privacy = '/settings/privacy';

  /// TEE verification log (Prüfprotokoll) and GPU check setting (WP52).
  static const attestationLog = '/settings/privacy/tee';

  /// Costs.
  static const costs = '/settings/costs';

  /// Assistant (default assistant, name, persona).
  static const assistant = '/settings/assistant';

  /// Voice: Whisper model, language, speech output.
  static const voice = '/settings/voice';

  /// Obsidian vault, daily notes, search index.
  static const obsidian = '/settings/obsidian';

  /// Design gallery (debug builds only).
  static const gallery = '/debug/gallery';
}
