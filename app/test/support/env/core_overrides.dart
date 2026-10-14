import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/routing.dart';
import 'package:wendelin_agent/wendelin_agent.dart';

import '../test_env.dart';

/// Overrides of the core providers: clock, database, secrets, start
/// settings, device and the network.
List<Override> coreOverrides(TestEnv env) => [
  clockProvider.overrideWithValue(env.clock),
  storageProvider.overrideWithValue(env.storage),
  secretStoreProvider.overrideWithValue(env.secrets),
  startupProvider.overrideWithValue(env.startup),
  deviceInfoProvider.overrideWithValue(
    const DeviceInfo(locale: 'de-DE', timeZone: 'Europe/Berlin'),
  ),
  networkStatusProvider.overrideWithValue(env.network),
];
