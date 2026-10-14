/// Web integration: fetching with guard, search backends.
///
/// Entry point of one integration; `wendelin_integrations.dart` re-exports it.
library;

export 'src/web/fetch_guard.dart';
export 'src/web/web_fetcher.dart';
export 'src/web/web_integration.dart';
export 'src/web/web_search_backend.dart'
    show
        BraveSearchBackend,
        SearxngBackend,
        TavilyBackend,
        WebSearchBackend,
        WebSearchResult;
