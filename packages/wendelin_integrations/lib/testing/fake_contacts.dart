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

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<List<ContactEntry>> all() async {
    enter('all');
    if (!permission) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        'Kein Zugriff auf die Kontakte.',
      );
    }
    return contacts;
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
