import 'dart:async';

import 'package:wendelin_integrations/common.dart'
    show PortErrorKind, ReconnectFailure;
import 'package:wendelin_integrations/home_assistant.dart';

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
    final ha = HaIntegration(
      deps.api,
      deps.store,
      deps.store,
      onError: (_, kind) => d.reportError?.call('ha', pausedError, kind),
      onRecovered: () => d.clearError?.call('ha'),
    );
    // App start: compare the approved devices with Home Assistant (at most
    // daily; failures keep the old state).
    unawaited(ha.context.syncIfDue());
    return ha;
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
