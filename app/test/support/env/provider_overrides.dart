import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wendelin/di/providers.dart';

import '../test_env.dart';

/// Overrides of the provider configuration: adapter factory and the stored
/// or scripted configuration.
List<Override> withProviders(TestEnv env) => [
  if (env.llmFactory case final f?)
    llmProviderFactoryProvider.overrideWithValue(f),
  if (!env.storedProfiles)
    storedProviderConfigProvider.overrideWith(
      (ref) async => env.providerConfigError == null
          ? env.providerConfig
          : throw env.providerConfigError!,
    ),
];
