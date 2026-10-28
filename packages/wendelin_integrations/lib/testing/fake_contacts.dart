import '../src/common/port_exception.dart';
import '../src/contacts/contacts_ports.dart';
import 'fake_failures.dart';

/// In-memory [ContactsPort]. Without [permission] [all] throws
/// `permissionDenied`.
final class FakeContactsPort with FakeFailures implements ContactsPort {
  /// Creates the fake with [contacts].
  FakeContactsPort({this.contacts = const [], this.permission = true});

  /// The address book.
  List<ContactEntry> contacts;

  /// Whether reading is allowed.
  bool permission;

  /// The `fields` of every [all] call, in order.
  final List<Set<ContactField>> requested = [];

  /// The hits (names) and `fields` of every [details] call, in order.
  final List<({List<String> names, Set<ContactField> fields})> detailed = [];

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<List<ContactEntry>> all({
    Set<ContactField> fields = defaultContactFields,
  }) async {
    enter('all');
    requested.add(fields);
    if (!permission) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        'Kein Zugriff auf die Kontakte.',
      );
    }
    // Like the real port: phone and mail as requested, the extras (address,
    // birthday, organization) only through [details]; `ref` is the index.
    return [
      for (var i = 0; i < contacts.length; i++)
        ContactEntry(
          name: contacts[i].name,
          phones: fields.contains(ContactField.phone)
              ? contacts[i].phones
              : const [],
          emails: fields.contains(ContactField.email)
              ? contacts[i].emails
              : const [],
          ref: '$i',
        ),
    ];
  }

  @override
  Future<List<ContactEntry>> details(
    List<ContactEntry> hits,
    Set<ContactField> fields,
  ) async {
    enter('details');
    detailed.add((names: [for (final h in hits) h.name], fields: fields));
    if (!permission) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        'Kein Zugriff auf die Kontakte.',
      );
    }
    return [
      for (final h in hits)
        if (int.tryParse(h.ref ?? '') case final i? when i < contacts.length)
          h.withDetails(
            ContactEntry(
              name: h.name,
              addresses: fields.contains(ContactField.address)
                  ? contacts[i].addresses
                  : const [],
              birthday: fields.contains(ContactField.birthday)
                  ? contacts[i].birthday
                  : null,
              organization: fields.contains(ContactField.organization)
                  ? contacts[i].organization
                  : null,
            ),
          )
        else
          h,
    ];
  }
}

/// A [PhonePort] that records instead of sending and calling.
final class FakePhonePort with FakeFailures implements PhonePort {
  /// Creates the fake.
  FakePhonePort({this.smsAllowed = true, this.callAllowed = true});

  /// Whether `SEND_SMS` is granted.
  bool smsAllowed;

  /// Whether `CALL_PHONE` is granted (else the dialer opens).
  bool callAllowed;

  /// Sent SMS: number and text.
  final List<({String number, String text})> sent = [];

  /// Calls placed directly.
  final List<String> called = [];

  /// Numbers shown in the dialer.
  final List<String> dialed = [];

  @override
  Future<bool> canSendSms() async => smsAllowed;

  @override
  Future<void> sendSms(String number, String text) async {
    enter('sendSms');
    if (!smsAllowed) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        'Keine SMS-Berechtigung.',
      );
    }
    sent.add((number: number, text: text));
  }

  @override
  Future<CallPlacement> call(String number) async {
    enter('call');
    if (callAllowed) {
      called.add(number);
      return CallPlacement.direct;
    }
    dialed.add(number);
    return CallPlacement.dialer;
  }
}
