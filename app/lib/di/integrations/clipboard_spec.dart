import 'package:wendelin_integrations/clipboard.dart';

import 'integration_spec.dart';

/// Clipboard.
final clipboardSpec = IntegrationSpec(
  id: 'clipboard',
  create: (d) => ClipboardIntegration(d.ports.clipboard),
);
