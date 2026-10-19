import 'package:wendelin_integrations/home_assistant.dart';
import 'package:wendelin_integrations/common.dart'
    show PortErrorKind, ReconnectFailure;

import '../core_providers.dart';
import '../home_assistant.dart';
import 'integration_spec.dart';

typedef _HaDeps = ({HaApi api, SecretStoreHa store});

/// Home Assistant (home network or Tailscale).
final haSpec = IntegrationSpec(
  id: 'ha',
  // Talks to the user's own instance: not in the demo mode.
  prepare: (ref) => ref.watch(demoModeProvider)
      ? null
      : (api: ref.watch(haApiProvider), store: ref.watch(haStoreProvider)),
  isSupported: (d) => d.extra<_HaDeps>('ha') != null,
  create: (d) {
    final deps = d.extra<_HaDeps>('ha')!;
    return HaIntegration(
      deps.api,
      deps.store,
      deps.store,
      onError: (message) => d.reportError?.call('ha', '$message · pausiert'),
      onRecovered: () => d.clearError?.call('ha'),
    );
  },
  retry: (
    run: (i) async => i is HaIntegration
        ? i.reconnect()
        : const ReconnectFailure(
            'ha',
            PortErrorKind.permissionDenied,
            'Home Assistant ist nicht eingerichtet.',
          ),
  ),
);
