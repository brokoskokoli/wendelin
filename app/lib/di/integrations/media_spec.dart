import 'package:wendelin_integrations/media.dart';

import 'integration_spec.dart';

/// Media control. Switching it on opens the system page for the
/// notification access (reading what plays and seeking need it, the media
/// keys do not); the answer comes back through the setup state. The
/// explanation is translated (`integrationsMediaRationale`).
final mediaSpec = IntegrationSpec(
  id: 'media',
  create: (d) => MediaIntegration(d.ports.media!, d.ports.apps),
  isSupported: (d) => d.ports.media != null,
  requestPermission: (d) async {
    final media = d.ports.media!;
    if (await media.hasSessionAccess()) return true;
    await media.openSessionAccessSettings();
    return false;
  },
);
