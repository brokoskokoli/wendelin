import 'package:flutter/widgets.dart';

import '../routes.dart';
import 'bring_screen.dart';
import 'http_tool_editor_screen.dart';
import 'http_tools_screen.dart';
import 'lists_screen.dart';
import 'mcp/mcp_servers_screen.dart';
import 'obsidian_screen.dart';
import 'web_search_screen.dart';

/// Routes of the settings pages of single integrations. A new integration
/// with its own settings page adds its lines here.
Map<String, WidgetBuilder> integrationRoutes() => {
  AppRoutes.mcpServers: (_) => const McpServersScreen(),
  AppRoutes.httpTools: (_) => const HttpToolsScreen(),
  AppRoutes.httpToolNew: (_) => const HttpToolEditorScreen(),
  AppRoutes.bring: (_) => const BringScreen(),
  AppRoutes.lists: (_) => const ListsScreen(),
  AppRoutes.webSearch: (_) => const WebSearchScreen(),
  AppRoutes.obsidian: (_) => const ObsidianScreen(),
};
