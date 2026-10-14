import 'package:wendelin_integrations/web.dart';

import '../core_providers.dart';
import '../preferences.dart';
import '../web_search.dart';
import 'integration_spec.dart';

/// Web: fetch always, search once a service is configured.
final webSpec = IntegrationSpec(
  id: 'web',
  // The configured search service; `null` = only `web__fetch` (settings →
  // Web-Suche configures one).
  prepare: (ref) => switch (ref.watch(webSearchConfigProvider)) {
    null => null,
    final config => StoredKeyWebSearch(
      config,
      secrets: ref.watch(secretStoreProvider),
      client: ref.watch(httpClientProvider),
    ),
  },
  create: (d) => WebIntegration(
    fetcher: WebFetcher(client: d.httpClient),
    searchBackend: d.extra<WebSearchBackend>('web'),
  ),
);
