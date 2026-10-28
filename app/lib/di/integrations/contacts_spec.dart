import 'package:wendelin_integrations/contacts.dart';
import 'package:wendelin_integrations/maps.dart';

import '../navigation_apps.dart';
import '../providers.dart';
import '../sms_drafts.dart';
import 'integration_spec.dart';

/// What `contactsSpec.prepare` reads for the integration.
typedef ContactsPrepared = ({
  SmsDraftEdits edits,
  NavigationStarter? navigation,
});

/// Contacts, SMS and phone calls. Switching it on asks for the address
/// book, SMS and phone permission together; sending and calling stay behind
/// the preview confirmation. Not allowed on a locked device. The
/// explanation is translated (`integrationsContactsRationale`).
///
/// `contacts__navigate` (WP164 C) shares the navigation app choice with
/// `maps__navigate`; it is offered only while a navigation app is active.
final contactsSpec = IntegrationSpec(
  id: 'contacts',
  prepare: (ref) {
    final launcher = ref.watch(platformPortsProvider).mapsLauncher;
    return (
      edits: ref.watch(smsDraftEditsProvider),
      navigation: launcher == null
          ? null
          : NavigationStarter(launcher, appNavigationApps(ref)),
    );
  },
  isSupported: (d) => d.ports.contacts != null && d.ports.phone != null,
  create: (d) {
    final prepared = d.extra<ContactsPrepared>('contacts');
    return ContactsIntegration(
      d.ports.contacts!,
      d.ports.phone!,
      edits: prepared?.edits,
      navigation: prepared?.navigation,
    );
  },
  requestPermission: (d) async =>
      await d.ports.requestContactsPermission?.call() ?? true,
);
