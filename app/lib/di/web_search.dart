import 'package:http/http.dart' as http;
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'preference_models.dart';

/// [WebSearchBackend] for [config] that reads its API key from the
/// [SecretStore] on every search, so the key never lives in app state and a
/// changed key takes effect at once.
final class StoredKeyWebSearch implements WebSearchBackend {
  /// Creates the backend.
  StoredKeyWebSearch(
    this.config, {
    required this.secrets,
    required this.client,
  });

  /// Service and base URL.
  final WebSearchConfig config;

  /// Where the key is.
  final SecretStore secrets;

  /// HTTP client.
  final http.Client client;

  @override
  String get id => config.kind.name;

  @override
  String get displayName => config.kind.label;

  @override
  Future<List<WebSearchResult>> search(
    String query, {
    int count = 5,
    String? language,
    CancelToken? cancel,
  }) async => (await _backend()).search(
    query,
    count: count,
    language: language,
    cancel: cancel,
  );

  Future<WebSearchBackend> _backend() async {
    switch (config.kind) {
      case WebSearchKind.searxng:
        final url = Uri.tryParse(config.baseUrl ?? '');
        if (url == null || !url.hasScheme) {
          throw const PortException(
            PortErrorKind.unavailable,
            'SearXNG: Adresse fehlt in den Einstellungen.',
          );
        }
        return SearxngBackend(baseUrl: url, client: client);
      case WebSearchKind.brave || WebSearchKind.tavily:
        final key = await secrets.read(config.kind.secretRef);
        if (key == null || key.trim().isEmpty) {
          throw PortException(
            PortErrorKind.unavailable,
            '${config.kind.label}: API-Key fehlt in den Einstellungen.',
          );
        }
        return config.kind == WebSearchKind.brave
            ? BraveSearchBackend(apiKey: key.trim(), client: client)
            : TavilyBackend(apiKey: key.trim(), client: client);
    }
  }
}
