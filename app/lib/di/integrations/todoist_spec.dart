import 'package:wendelin_integrations/todoist.dart';

import '../core_providers.dart';
import '../todoist.dart';
import 'integration_spec.dart';

typedef _TodoistDeps = ({TodoistApi api, TodoistSecrets secrets});

/// Todoist tasks (personal API token, Einstellungen → Todoist).
final todoistSpec = IntegrationSpec(
  id: 'todoist',
  // Talks to a real account: not in the demo mode.
  prepare: (ref) => ref.watch(demoModeProvider)
      ? null
      : (
          api: ref.watch(todoistApiProvider),
          secrets: ref.watch(todoistSecretsProvider),
        ),
  isSupported: (d) => d.extra<_TodoistDeps>('todoist') != null,
  create: (d) {
    final deps = d.extra<_TodoistDeps>('todoist')!;
    return TodoistIntegration(
      deps.api,
      deps.secrets,
      onError: (m) => d.reportError?.call('todoist', '$m · pausiert'),
      onRecovered: () => d.clearError?.call('todoist'),
    );
  },
  retry: (
    label: 'Erneut versuchen',
    run: (i) async => i is TodoistIntegration
        ? i.reconnect()
        : 'Todoist ist nicht eingerichtet.',
  ),
);
