import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/integration_specs.dart';
import 'package:wendelin/di/preference_models.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'test_env.dart';

/// Every integration of the real registry ([builtInIntegrationSpecs]), built
/// by the app's own provider from fakes, with all optional tools present
/// (e.g. a web search service is configured). Tests that walk "all
/// integrations" use this, so a new integration needs no line in them.
///
/// Call inside a test (registers the container's teardown).
Map<String, Integration> allBuiltInIntegrations() {
  final c = ProviderContainer(
    overrides: TestEnv(
      startup: StartupSettings(
        enabledIntegrations: {for (final s in builtInIntegrationSpecs) s.id},
        webSearch: const WebSearchConfig(
          WebSearchKind.searxng,
          baseUrl: 'https://search.invalid',
        ),
      ),
    ).overrides,
    retry: (_, _) => null,
  );
  addTearDown(c.dispose);
  return c.read(integrationsProvider);
}
