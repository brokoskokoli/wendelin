/// Named routes of the app.
abstract final class AppRoutes {
  /// Main screen.
  static const home = '/';

  /// Settings overview.
  static const settings = '/settings';

  /// New provider profile (setup dialog).
  static const providerSetup = '/settings/provider';

  /// Provider profiles, default and escalation chain.
  static const providers = '/settings/providers';

  /// Routing rules and escalation chains (WP26).
  static const routing = '/settings/routing';

  /// Integrations.
  static const integrations = '/settings/integrations';

  /// MCP servers (WP27).
  static const mcpServers = '/settings/mcp';

  /// Declarative HTTP tools (WP28).
  static const httpTools = '/settings/http-tools';

  /// Lists (K6).
  static const lists = '/settings/lists';

  /// Web search service.
  static const webSearch = '/settings/web';

  /// Memory entries.
  static const memory = '/settings/memory';

  /// Privacy and logs.
  static const privacy = '/settings/privacy';

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
