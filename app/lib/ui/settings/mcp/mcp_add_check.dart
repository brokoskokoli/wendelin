import 'package:wendelin_mcp/wendelin_mcp.dart';

import '../../../l10n/l10n.dart';

/// Why the entries of „+ Server“ cannot be saved, or `null` when they can.
/// Plain `http` only passes into the home network ([checkServerUrl]).
String? mcpAddError(
  AppLocalizations l, {
  required String name,
  required String urlText,
  required McpAuthKind auth,
  required String headerName,
}) {
  final url = Uri.tryParse(urlText);
  if (name.isEmpty) return l.mcpCheckNameMissing;
  if (McpTemplate.hasPlaceholder(urlText)) {
    return l.mcpCheckPlaceholders;
  }
  if (url == null || !url.hasScheme || url.host.isEmpty) {
    return l.mcpCheckUrlIncomplete;
  }
  try {
    checkServerUrl(url);
  } on McpException catch (e) {
    return e.message;
  }
  if (auth == McpAuthKind.headers && headerName.trim().isEmpty) {
    return l.mcpCheckHeaderMissing;
  }
  return null;
}
