/// How a server authenticates, as chosen in the form.
enum McpAuthKind {
  /// None (e.g. only reachable over Tailscale).
  none('Keine'),

  /// `Authorization: Bearer <token>`.
  bearer('Bearer-Token'),

  /// Own headers with secret values.
  headers('Eigene Header'),

  /// OAuth 2.1 login in the browser.
  oauth('OAuth-Anmeldung');

  const McpAuthKind(this.label);

  /// German label.
  final String label;
}

/// A known server type to start from (concept: „Vorlagen“): name, URL
/// pattern and the kind of authentication.
final class McpTemplate {
  /// Creates a template.
  const McpTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.urlPattern,
    required this.auth,
    this.authHint,
  });

  /// Stable id.
  final String id;

  /// Suggested server name.
  final String name;

  /// What the server offers (one line).
  final String description;

  /// URL with placeholders in angle brackets, e.g. `<homeserver>`.
  final String urlPattern;

  /// Default authentication.
  final McpAuthKind auth;

  /// Where the token comes from.
  final String? authHint;

  /// Whether [urlPattern] still has placeholders to replace.
  static bool hasPlaceholder(String url) => RegExp('<[^>]*>').hasMatch(url);

  /// The free entry („Eigener Server“).
  static const custom = McpTemplate(
    id: 'custom',
    name: '',
    description: 'Beliebiger Server mit Streamable HTTP oder SSE',
    urlPattern: 'https://',
    auth: McpAuthKind.none,
  );

  /// Templates in the order shown.
  static const all = [
    McpTemplate(
      id: 'home_assistant',
      name: 'Home Assistant',
      description: 'Licht, Szenen, Sensoren (Integration „MCP Server“)',
      urlPattern: 'http://homeassistant.local:8123/api/mcp',
      auth: McpAuthKind.bearer,
      authHint: 'Langlebiges Zugriffstoken aus deinem Home-Assistant-Profil',
    ),
    McpTemplate(
      id: 'obsidian',
      name: 'Obsidian',
      description:
          'Vault auf dem Desktop (obsidian-mcp-server, Local REST API)',
      urlPattern: 'http://<rechner>.ts.net:3010/mcp',
      auth: McpAuthKind.bearer,
      authHint: 'Token aus der Konfiguration des Servers',
    ),
    McpTemplate(
      id: 'dav',
      name: 'Kalender (CalDAV)',
      description: 'Kalender auf dem Homeserver über dav-mcp',
      urlPattern: 'http://<homeserver>.ts.net:3000/mcp',
      auth: McpAuthKind.bearer,
      authHint: 'Bearer-Token aus der Konfiguration von dav-mcp',
    ),
    custom,
  ];
}
