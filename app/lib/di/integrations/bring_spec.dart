import 'package:wendelin_integrations/bring.dart';

import '../app_requirements.dart';
import '../bring.dart';
import '../core_providers.dart';
import 'integration_spec.dart';

typedef _BringDeps = ({BringApi api, BringSecrets secrets});

/// Bring! shopping lists.
final bringSpec = IntegrationSpec(
  id: 'bring',
  // Bring! talks to a real account: not in the demo mode.
  prepare: (ref) => ref.watch(demoModeProvider)
      ? null
      : (
          api: ref.watch(bringApiProvider),
          secrets: ref.watch(bringSecretsProvider),
        ),
  // Unofficial API with the user's account (Einstellungen → Bring!); the
  // app is only the fallback for sharing items when the API fails.
  isSupported: (d) => d.extra<_BringDeps>('bring') != null,
  requiredApp: KnownApps.bring.optional(
    'Bring!-App fehlt: kein Ausweg über „Teilen“',
  ),
  create: (d) {
    final deps = d.extra<_BringDeps>('bring')!;
    return BringIntegration(
      deps.api,
      deps.secrets,
      onError: (message) => d.reportError?.call('bring', '$message · pausiert'),
      onRecovered: () => d.clearError?.call('bring'),
    );
  },
  retry: (
    label: 'Erneut versuchen',
    run: (i) async => i is BringIntegration
        ? i.reconnect()
        : 'Bring! ist nicht eingerichtet.',
  ),
);
