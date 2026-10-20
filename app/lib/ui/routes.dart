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

  /// Todoist API token and state (WP89).
  static const todoist = '/settings/todoist';

  /// Google Tasks client, login and state (WP89b).
  static const googleTasks = '/settings/google_tasks';

  /// Home Assistant address, token and devices (WP91).
  static const homeAssistant = '/settings/home_assistant';

  /// Spotify login and state (WP84).
  static const spotify = '/settings/spotify';

  /// Lists (K6).
  static const lists = '/settings/lists';

  /// Web search service.
  static const webSearch = '/settings/web';

  /// Station mode settings (WP99).
  static const station = '/settings/station';

  /// Weather service and home place.
  static const weather = '/settings/weather';

  /// Memory entries.
  static const memory = '/settings/memory';

  /// Privacy and logs.
  static const privacy = '/settings/privacy';

  /// Audit log page (Prüfprotokoll, WP65).
  static const auditLog = '/settings/privacy/audit';

  /// TEE verification log (Prüfprotokoll) and GPU check setting (WP52).
  static const attestationLog = '/settings/privacy/tee';

  /// Costs.
  static const costs = '/settings/costs';

  /// Assistant (default assistant, name, persona).
  static const assistant = '/settings/assistant';

  /// App language (WP79).
  static const appLanguage = '/settings/app-language';

  /// Voice: Whisper model, language, speech output.
  static const voice = '/settings/voice';

  /// Voice → Stimmen: offline voices per language (WP66).
  static const voices = '/settings/voice/voices';

  /// Voice → Messwerte: latency, RTF and memory per utterance (WP103).
  static const voiceMetrics = '/settings/voice/metrics';

  /// Wake word: learn the voice, calibrate, try (WP60).
  static const wakeWord = '/settings/voice/wake';

  /// Speaker recognition: switch, model, people (WP92a).
  static const speaker = '/settings/voice/speaker';

  /// Obsidian vault, daily notes, search index.
  static const obsidian = '/settings/obsidian';

  /// Design gallery (debug builds only).
  static const gallery = '/debug/gallery';
}
