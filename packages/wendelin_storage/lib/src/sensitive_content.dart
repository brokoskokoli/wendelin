/// Kind of sensitive content that must never be stored in memory.
enum SensitiveKind {
  /// A payment card number (13–19 digits, Luhn-valid).
  cardNumber,

  /// An IBAN.
  iban,

  /// A password, PIN or similar credential ("Passwort: …").
  credential,
}

/// Thrown when text to be remembered contains sensitive content.
///
/// The message never repeats the sensitive text.
final class SensitiveContentException implements Exception {
  /// Creates the exception for [kind].
  const SensitiveContentException(this.kind);

  /// What was detected.
  final SensitiveKind kind;

  /// German, user-facing explanation.
  String get message => switch (kind) {
    SensitiveKind.cardNumber =>
      'Kartennummern werden aus Sicherheitsgründen nicht gespeichert.',
    SensitiveKind.iban =>
      'Kontonummern (IBAN) werden aus Sicherheitsgründen nicht gespeichert.',
    SensitiveKind.credential =>
      'Passwörter und PINs werden aus Sicherheitsgründen nicht gespeichert.',
  };

  @override
  String toString() => 'SensitiveContentException(${kind.name}): $message';
}

/// Detects content that must not be stored (concept: "Passwörter und
/// Kartennummern werden gar nicht gespeichert").
///
/// - **Card numbers**: digit groups separated by up to three spaces, dots or
///   dashes; every run of consecutive whole groups with 13–19 digits in
///   total that starts with 2–6 (Mastercard, Amex, Visa, Discover, …) is
///   Luhn-checked. Runs starting with `+` (phone numbers) are ignored; a
///   single unseparated run longer than 19 digits is not a card number.
/// - **IBAN**: two letters (any case), two check digits, then 11–30
///   alphanumerics (spaces allowed between them), at least 6 of them digits.
///   The mod-97 checksum is deliberately *not* required, so mistyped IBANs
///   are rejected too.
/// - **Credentials**: a keyword (Passwort, Kennwort, Password, PIN, PIN-Code,
///   Passcode, Zugangscode, Zugangsdaten, Geheimzahl) followed, within up to
///   four words, by `:`, `=`, "ist", "lautet", "heißt", "war" or "is"/"was"
///   and a value ("Das Passwort für das WLAN ist …"), or followed directly by
///   a value containing a digit ("PIN 1234", "Passwort hunter2").
SensitiveKind? detectSensitiveContent(String text) {
  if (_containsCardNumber(text)) return SensitiveKind.cardNumber;
  if (_containsIban(text)) return SensitiveKind.iban;
  if (_credential.hasMatch(text)) return SensitiveKind.credential;
  return null;
}

/// Throws [SensitiveContentException] if [text] contains sensitive content.
void checkNotSensitive(String text) {
  final kind = detectSensitiveContent(text);
  if (kind != null) throw SensitiveContentException(kind);
}

/// Luhn checksum over a string of ASCII digits.
bool luhnValid(String digits) {
  var sum = 0;
  var doubleIt = false;
  for (var i = digits.length - 1; i >= 0; i--) {
    var d = digits.codeUnitAt(i) - 0x30;
    if (doubleIt) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
    doubleIt = !doubleIt;
  }
  return sum % 10 == 0;
}

// Digit groups joined by short separators, not glued to other digits. A
// leading `+` is captured so phone numbers can be skipped as a whole.
final _digitRun = RegExp(r'(\+\s?)?(?<!\d)\d+(?:[ .\-]{1,3}\d+)*(?!\d)');
final _separator = RegExp(r'[ .\-]+');

bool _containsCardNumber(String text) {
  for (final m in _digitRun.allMatches(text)) {
    if (m.group(1) != null) continue;
    final groups = m.group(0)!.split(_separator);
    for (var start = 0; start < groups.length; start++) {
      final first = groups[start].codeUnitAt(0);
      if (first < 0x32 || first > 0x36) continue; // '2'..'6'
      var digits = '';
      for (var end = start; end < groups.length; end++) {
        digits += groups[end];
        if (digits.length > 19) break;
        if (digits.length >= 13 && luhnValid(digits)) return true;
      }
    }
  }
  return false;
}

final _ibanCandidate = RegExp(
  r'(?<![A-Za-z0-9])[A-Za-z]{2}\d{2}(?: *[A-Za-z0-9]){11,30}(?![A-Za-z0-9])',
);

bool _containsIban(String text) {
  for (final m in _ibanCandidate.allMatches(text)) {
    final bban = m.group(0)!.substring(4).replaceAll(' ', '');
    final digits = bban.replaceAll(RegExp('[^0-9]'), '').length;
    if (digits >= 6) return true;
  }
  return false;
}

const _keyword =
    r'(?<![\p{L}\p{N}])'
    r'(?:passw(?:o|ö)rt(?:er|e)?|kennwort|password|passcode|'
    r'pin(?:-?code|-?nummer)?|zugangscode|zugangsdaten|geheimzahl)'
    r'(?![\p{L}\p{N}])';

final _credential = RegExp(
  // Keyword, up to four words, then an assignment and a value.
  '$_keyword'
  r'(?:\s+[\p{L}\p{N}-]+){0,4}?'
  r'(?:\s*[:=]|\s+(?:ist|lautet|heißt|heisst|war|is|was)(?![\p{L}\p{N}]))'
  r'\s*\S'
  // Or keyword directly followed by a value containing a digit.
  '|$_keyword'
  r'\s*[:=]?\s+(?=[^\s]*\p{N})[^\s]+',
  caseSensitive: false,
  unicode: true,
);
