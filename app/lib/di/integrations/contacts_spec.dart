import 'package:wendelin_integrations/contacts.dart';

import '../sms_drafts.dart';
import 'integration_spec.dart';

/// Contacts, SMS and phone calls. Switching it on asks for the address
/// book, SMS and phone permission together; sending and calling stay behind
/// the preview confirmation. Not allowed on a locked device. The
/// explanation is translated (`integrationsContactsRationale`).
final contactsSpec = IntegrationSpec(
  id: 'contacts',
  prepare: (ref) => ref.watch(smsDraftEditsProvider),
  isSupported: (d) => d.ports.contacts != null && d.ports.phone != null,
  create: (d) => ContactsIntegration(
    d.ports.contacts!,
    d.ports.phone!,
    edits: d.extra<SmsDraftEdits>('contacts'),
  ),
  requestPermission: (d) async =>
      await d.ports.requestContactsPermission?.call() ?? true,
);
