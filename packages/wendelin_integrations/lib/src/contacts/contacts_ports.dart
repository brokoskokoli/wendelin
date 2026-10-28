import 'package:wendelin_core/wendelin_core.dart';

/// One phone number of a [ContactEntry].
final class ContactPhone {
  /// Creates a number with its [label] (`Mobil`, `Privat`, …; may be empty).
  const ContactPhone(this.number, {this.label = ''});

  /// The number as stored in the address book.
  final String number;

  /// Kind of the number as the user named it.
  final String label;

  /// JSON form for the model.
  Map<String, Object?> toJson() => {
    'number': number,
    if (label.isNotEmpty) 'label': label,
  };
}

/// A postal address of a [ContactEntry].
final class ContactAddress {
  /// Creates an address with its [label] (`Privat`, `Arbeit`, …; may be
  /// empty).
  const ContactAddress(this.address, {this.label = ''});

  /// The formatted address as stored in the address book.
  final String address;

  /// Kind of the address as the user named it.
  final String label;

  /// JSON form for the model.
  Map<String, Object?> toJson() => {
    'address': address,
    if (label.isNotEmpty) 'label': label,
  };
}

/// A piece of a contact `contacts__find` may be asked for (`fields`). Notes
/// are deliberately not part of it.
enum ContactField {
  /// Phone numbers.
  phone,

  /// Mail addresses.
  email,

  /// Postal addresses.
  address,

  /// Birthday.
  birthday,

  /// Company or organization.
  organization;

  /// Parses the wire name, `null` if unknown.
  static ContactField? byName(String name) {
    for (final f in values) {
      if (f.name == name) return f;
    }
    return null;
  }
}

/// What is read without a `fields` request: phone numbers and mail
/// addresses.
const defaultContactFields = {ContactField.phone, ContactField.email};

/// A person in the address book.
final class ContactEntry {
  /// Creates an entry.
  const ContactEntry({
    required this.name,
    this.phones = const [],
    this.emails = const [],
    this.addresses = const [],
    this.birthday,
    this.organization,
    this.ref,
  });

  /// Opaque handle of the port for [ContactsPort.details] (the platform's
  /// contact id). Never part of any JSON form: it does not reach the model.
  final String? ref;

  /// Display name.
  final String name;

  /// Phone numbers.
  final List<ContactPhone> phones;

  /// Mail addresses.
  final List<String> emails;

  /// Postal addresses.
  final List<ContactAddress> addresses;

  /// Birthday as stored (`1985-03-14`, or `--03-14` without a year).
  final String? birthday;

  /// Company or organization.
  final String? organization;

  /// This entry with [addresses], [birthday] and [organization] taken from
  /// [other] (the details of the same contact).
  ContactEntry withDetails(ContactEntry other) => ContactEntry(
    name: name,
    phones: phones,
    emails: emails,
    addresses: other.addresses,
    birthday: other.birthday,
    organization: other.organization,
    ref: ref,
  );

  /// JSON form for the model without a `fields` request: phones and mail
  /// addresses only.
  Map<String, Object?> toJson() => {
    'name': name,
    'phones': [for (final p in phones) p.toJson()],
    if (emails.isNotEmpty) 'emails': emails,
  };

  /// JSON form with exactly the requested [fields] (plus the name). Lists
  /// the model asked for are present even if empty, so "none stored" is
  /// visible; birthday and organization are left out when missing.
  Map<String, Object?> toJsonFor(Set<ContactField> fields) => {
    'name': name,
    if (fields.contains(ContactField.phone))
      'phones': [for (final p in phones) p.toJson()],
    if (fields.contains(ContactField.email)) 'emails': emails,
    if (fields.contains(ContactField.address))
      'addresses': [for (final a in addresses) a.toJson()],
    if (fields.contains(ContactField.birthday) && birthday != null)
      'birthday': birthday,
    if (fields.contains(ContactField.organization) && organization != null)
      'organization': organization,
  };
}

/// Read access to the address book.
///
/// Implementations throw `PortException(permissionDenied)` without the
/// permission. Must pass `contactsPortContract`.
abstract interface class ContactsPort {
  /// Whether reading contacts is allowed.
  Future<bool> hasPermission();

  /// The search index: all contacts that have a phone number or a mail
  /// address, or data of the requested extra [fields] (matching is done by
  /// [ContactsFinder], so it is the same on every platform). Only phone
  /// numbers and mail addresses are filled in (if requested); address,
  /// birthday and organization are not read here, see [details].
  Future<List<ContactEntry>> all({
    Set<ContactField> fields = defaultContactFields,
  });

  /// Reads address, birthday and organization (as far as in [fields]) of
  /// the contacts [hits] only, so that data beyond phone and mail is never
  /// loaded for the whole address book. Returns the hits in order, with the
  /// extras filled in; a hit the platform no longer knows comes back
  /// unchanged. Entries without [ContactEntry.ref] are returned as they are.
  Future<List<ContactEntry>> details(
    List<ContactEntry> hits,
    Set<ContactField> fields,
  );
}

/// How [PhonePort.call] started the call.
enum CallPlacement {
  /// The call was placed right away (`CALL_PHONE` granted).
  direct,

  /// The dialer was opened with the number; the user presses call.
  dialer,
}

/// SMS and phone calls of the device.
///
/// Callers confirm with the user **before** calling [sendSms] or [call]; the
/// port itself does not ask.
abstract interface class PhonePort {
  /// Whether sending SMS is allowed (`SEND_SMS`).
  Future<bool> canSendSms();

  /// Sends [text] as SMS to [number] (long texts in several parts).
  /// Throws `PortException(permissionDenied)` without the permission and
  /// `unsupported` on a device without telephony.
  Future<void> sendSms(String number, String text);

  /// Calls [number]: directly with `CALL_PHONE`, else the dialer opens.
  Future<CallPlacement> call(String number);
}

/// Draft texts the user changed in the preview before sending.
///
/// The preview (UI) records an edit with [set]; the tool [take]s it when it
/// is confirmed. Only the UI writes here, never the model, so a text
/// changed by the user is sent exactly as shown and nothing else can slip
/// in. Keyed by recipient and the original text.
final class SmsDraftEdits {
  final Map<String, String> _edited = {};

  static String _key(String number, String original) =>
      '${normalizePhone(number)}\u0000$original';

  /// Remembers that the user changed [original] (to [edited]) for [number].
  /// Equal texts remove the edit.
  void set(String number, String original, String edited) {
    if (edited == original) {
      _edited.remove(_key(number, original));
    } else {
      _edited[_key(number, original)] = edited;
    }
  }

  /// Whether the user changed the text.
  bool isEdited(String number, String original) =>
      _edited.containsKey(_key(number, original));

  /// The user's text for [original], removed from the store; `null` if
  /// unchanged.
  String? take(String number, String original) =>
      _edited.remove(_key(number, original));

  /// Forgets the edit (declined or dismissed preview).
  void discard(String number, String original) =>
      _edited.remove(_key(number, original));
}

/// [number] without spaces, dashes and brackets; a leading `+` stays.
/// `null` if it is not a plausible phone number (3–20 digits).
String? cleanPhoneNumber(String number) {
  final t = number.trim();
  if (!RegExp(r'^\+?[\d\s\-()./]+$').hasMatch(t)) return null;
  final digits = t.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 3 || digits.length > 20) return null;
  return t.startsWith('+') ? '+$digits' : digits;
}

/// Digits of [number] for comparing numbers; `00` and `+` prefixes are
/// the same.
String normalizePhone(String number) {
  var d = number.replaceAll(RegExp(r'[^\d+]'), '');
  if (d.startsWith('00')) d = '+${d.substring(2)}';
  return d;
}

/// Whether two numbers are the same line: equal, or one has the country
/// code (`+`/`00`) and the other the national `0` form, so that the
/// international digits are a 1–3 digit country code plus the national
/// digits. Two numbers with country code must be exactly equal.
bool samePhone(String a, String b) {
  final x = normalizePhone(a);
  final y = normalizePhone(b);
  if (x.replaceAll('+', '').isEmpty || y.replaceAll('+', '').isEmpty) {
    return false;
  }
  if (x == y) return true;
  final xi = x.startsWith('+');
  final yi = y.startsWith('+');
  if (xi == yi) return false;
  final intl = (xi ? x : y).substring(1);
  final national = xi ? y : x;
  if (!national.startsWith('0') || national.startsWith('00')) return false;
  final rest = national.substring(1);
  if (rest.length < 6) return false;
  final cc = intl.length - rest.length;
  return cc >= 1 && cc <= 3 && intl.endsWith(rest);
}

/// Name search over an address book.
final class ContactsFinder {
  /// Creates the finder on [port].
  const ContactsFinder(this.port);

  /// The address book.
  final ContactsPort port;

  /// Contacts matching [query] (folded: case, umlauts and punctuation
  /// ignored). Every word of the query must start a word of the name. An exact full-name match wins over partial matches, so
  /// „Anna“ finds only „Anna“ when she exists, not „Anna Meier“ as well.
  Future<List<ContactEntry>> find(
    String query, {
    int limit = 8,
    Set<ContactField> fields = defaultContactFields,
  }) async {
    final q = foldForMatch(query);
    if (q.isEmpty) return const [];
    final words = q.split(' ');
    bool hits(String name) {
      final parts = name.split(' ');
      return words.every((w) => parts.any((p) => p.startsWith(w)));
    }

    final matches = <ContactEntry>[];
    final exact = <ContactEntry>[];
    for (final c in await port.all(fields: fields)) {
      final name = foldForMatch(c.name);
      if (name == q) exact.add(c);
      if (hits(name)) matches.add(c);
    }
    final result = (exact.isNotEmpty ? exact : matches).take(limit).toList();
    // Data beyond phone and mail is read for the hits only.
    final extras = fields.difference(defaultContactFields);
    if (result.isEmpty || extras.isEmpty) return result;
    return port.details(result, extras);
  }

  /// The contact that owns [number], if any.
  Future<ContactEntry?> byNumber(String number) async {
    try {
      for (final c in await port.all()) {
        if (c.phones.any((p) => samePhone(p.number, number))) return c;
      }
    } on Object {
      // No permission or a failing address book: the number stands alone.
    }
    return null;
  }
}
