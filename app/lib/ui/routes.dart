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

  /// Integrations.
  static const integrations = '/settings/integrations';

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

  /// Assistant (name, persona).
  static const assistant = '/settings/assistant';

  /// Design gallery (debug builds only).
  static const gallery = '/debug/gallery';
}
