import 'package:wendelin_mcp/wendelin_mcp.dart';

/// Why the entries of „+ Server“ cannot be saved, or `null` when they can.
/// Plain `http` only passes into the home network ([checkServerUrl]).
String? mcpAddError({
  required String name,
  required String urlText,
  required McpAuthKind auth,
  required String headerName,
}) {
  final url = Uri.tryParse(urlText);
  if (name.isEmpty) return 'Bitte einen Namen angeben.';
  if (McpTemplate.hasPlaceholder(urlText)) {
    return 'Bitte die Platzhalter in <…> in der Adresse ersetzen.';
  }
  if (url == null || !url.hasScheme || url.host.isEmpty) {
    return 'Bitte eine vollständige Adresse angeben (https://…).';
  }
  try {
    checkServerUrl(url);
  } on McpException catch (e) {
    return e.message;
  }
  if (auth == McpAuthKind.headers && headerName.trim().isEmpty) {
    return 'Bitte den Namen des Headers angeben.';
  }
  return null;
}
