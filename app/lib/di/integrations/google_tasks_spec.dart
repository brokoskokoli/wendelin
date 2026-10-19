import 'package:wendelin_integrations/google_tasks.dart';
import 'package:wendelin_integrations/common.dart'
    show PortErrorKind, ReconnectFailure;

import '../core_providers.dart';
import '../google_tasks.dart';
import 'integration_spec.dart';

typedef _GoogleDeps = ({
  GoogleTasksApi api,
  GoogleOAuthApi oauth,
  GoogleTasksSecrets secrets,
});

/// Google Tasks (own Cloud project, OAuth with loopback redirect,
/// Einstellungen → Google Tasks).
final googleTasksSpec = IntegrationSpec(
  id: 'gtasks',
  // Talks to a real account: not in the demo mode.
  prepare: (ref) => ref.watch(demoModeProvider)
      ? null
      : (
          api: ref.watch(googleTasksApiProvider),
          oauth: ref.watch(googleOAuthProvider),
          secrets: ref.watch(googleTasksSecretsProvider),
        ),
  isSupported: (d) => d.extra<_GoogleDeps>('gtasks') != null,
  create: (d) {
    final deps = d.extra<_GoogleDeps>('gtasks')!;
    return GoogleTasksIntegration(
      deps.api,
      deps.oauth,
      deps.secrets,
      onError: (m) => d.reportError?.call('gtasks', '$m · pausiert'),
      onRecovered: () => d.clearError?.call('gtasks'),
    );
  },
  retry: (
    run: (i) async => i is GoogleTasksIntegration
        ? i.reconnect()
        : const ReconnectFailure(
            'gtasks',
            PortErrorKind.permissionDenied,
            'Google Tasks ist nicht eingerichtet.',
          ),
  ),
);
