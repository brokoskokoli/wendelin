import 'package:wendelin_core/wendelin_core.dart';

import 'contacts_ports.dart';
import 'contacts_tools.dart';

/// Contacts, SMS and phone calls: `contacts__find`, `sms__compose`,
/// `phone__call`.
///
/// Sending and calling are `external`: Wendelin shows a preview with name
/// and number and does it only after a tap or a clear spoken yes.
final class ContactsIntegration implements Integration {
  /// Creates the integration. [edits] receives the texts the user changed in
  /// the preview (shared with the UI).
  ContactsIntegration(this.contacts, this.phone, {SmsDraftEdits? edits})
    : edits = edits ?? SmsDraftEdits();

  /// Id of the permission setup step.
  static const permissionStep = 'contacts_permission';

  /// The address book.
  final ContactsPort contacts;

  /// SMS and calls.
  final PhonePort phone;

  /// Texts changed in the preview.
  final SmsDraftEdits edits;

  @override
  String get id => 'contacts';

  @override
  String get displayName => 'Kontakte & Telefon';

  @override
  String get iconId => 'contacts';

  @override
  Set<AppPlatform> get platforms => const {AppPlatform.android};

  /// Names, numbers and message texts are personal data.
  @override
  bool get sensitive => true;

  @override
  Future<Availability> checkAvailability() async => Availability.yes;

  @override
  List<SetupStep> get setup => const [
    SetupStep(
      id: permissionStep,
      kind: SetupStepKind.permission,
      label: 'Zugriff auf Kontakte, SMS und Telefon erlauben',
    ),
  ];

  @override
  Future<SetupState> setupState() async => SetupState(
    missingSteps: [if (!await contacts.hasPermission()) permissionStep],
  );

  @override
  late final List<Tool> tools = List.unmodifiable(<Tool>[
    ContactsFindTool(ContactsFinder(contacts)),
    SmsComposeTool(ContactsFinder(contacts), phone, edits),
    PhoneCallTool(ContactsFinder(contacts), phone),
  ]);
}
