import '../routes.dart';

/// The settings page where the missing setup of integration [id] happens,
/// or `null` if „Einrichten“ asks for a permission instead.
String? setupPageFor(String id) => switch (id) {
  'lists' || 'tasks' => AppRoutes.lists,
  'obsidian' => AppRoutes.obsidian,
  'web' => AppRoutes.webSearch,
  'weather' => AppRoutes.weather,
  'bring' => AppRoutes.bring,
  'todoist' => AppRoutes.todoist,
  'ha' => AppRoutes.homeAssistant,
  'spotify' => AppRoutes.spotify,
  // MCP servers: login or token on the server list (WP27).
  _ when id.startsWith('mcp_') => AppRoutes.mcpServers,
  _ => null,
};
