import 'package:meta/meta.dart';

/// Kind of sensitive content that must never be stored in memory (concept:
/// "Passwörter und Kartennummern werden gar nicht gespeichert").
enum SensitiveKind {
  /// A payment card number (13–19 digits, Luhn-valid).
  cardNumber,

  /// An IBAN.
  iban,

  /// A password, PIN, API key or similar credential.
  credential;

  /// German, user-facing reason. Never repeats the sensitive text.
  String get reason => switch (this) {
    cardNumber =>
      'Kartennummern werden aus Sicherheitsgründen nicht gespeichert.',
    iban =>
      'Kontonummern (IBAN) werden aus Sicherheitsgründen nicht gespeichert.',
    credential =>
      'Passwörter, PINs und Zugangsdaten werden aus Sicherheitsgründen '
          'nicht gespeichert.',
  };
}

/// Result of [detectSensitiveContent]: what was found and why it must not
/// be stored.
@immutable
final class SensitiveFinding {
  /// Creates a finding of [kind].
  const SensitiveFinding(this.kind);

  /// What was detected.
  final SensitiveKind kind;

  /// German, user-facing reason (see [SensitiveKind.reason]).
  String get reason => kind.reason;

  @override
  bool operator ==(Object other) =>
      other is SensitiveFinding && other.kind == kind;

  @override
  int get hashCode => kind.hashCode;

  @override
  String toString() => 'SensitiveFinding(${kind.name})';
}

/// Detects content that must not be stored; `null` if [text] is fine.
/// The single source for memory (storage repository, memory tool, fakes).
///
/// - **Card numbers**: digit groups separated by up to three spaces, dots or
///   dashes; every run of consecutive whole groups with 13–19 digits in
///   total that starts with 2–6 (Mastercard, Amex, Visa, Discover, …) is
///   Luhn-checked. Ignored: runs starting with `+` (phone numbers), 13-digit
///   numbers starting with 49 or 43 (German/Austrian phone numbers without
///   `+`), a single unseparated run longer than 19 digits.
/// - **IBAN**: two letters (any case), two check digits and a BBAN of 11–30
///   alphanumerics with at least 6 digits, written either compactly or in
///   groups of four separated by spaces (last group 1–4). The mod-97
///   checksum is deliberately *not* required, so mistyped IBANs are rejected
///   too.
/// - **Credentials**: a keyword (Passwort, Kennwort, Password, Passwd,
///   Passcode, PIN, PIN-Code, PUK, TAN, API-Key, Secret, Token, Zugangscode,
///   Zugangsdaten, Geheimzahl) followed, within up to four words, by `:`,
///   `=`, "ist", "lautet", "heißt", "war" or "is"/"was" and a value ("Das
///   Passwort für das WLAN ist …"), or followed directly by a value
///   containing a digit ("PIN 1234", "Passwort hunter2"); also API-key-like
///   tokens (`sk-…`, `pk_…`, `ghp_…`, `xoxb-…`, `tvly-…`, `AKIA…`).
///
/// Health and financial topics are not detected by keywords (too
/// unreliable); they are only saved on the user's explicit request.
SensitiveFinding? detectSensitiveContent(String text) {
  final kind = _containsCardNumber(text)
      ? SensitiveKind.cardNumber
      : _containsIban(text)
      ? SensitiveKind.iban
      : _credential.hasMatch(text) || _apiKey.hasMatch(text)
      ? SensitiveKind.credential
      : null;
  return kind == null ? null : SensitiveFinding(kind);
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
        if (digits.length >= 13 && !_isPhone(digits) && luhnValid(digits)) {
          return true;
        }
      }
    }
  }
  return false;
}

bool _isPhone(String digits) =>
    digits.length == 13 && (digits.startsWith('49') || digits.startsWith('43'));

final _ibanCandidate = RegExp(
  r'(?<![A-Za-z0-9])[A-Za-z]{2}\d{2}'
  r'(?:[A-Za-z0-9]{11,30}|(?: +[A-Za-z0-9]{4}){2,7}(?: +[A-Za-z0-9]{1,4})?)'
  r'(?![A-Za-z0-9])',
);

bool _containsIban(String text) {
  for (final m in _ibanCandidate.allMatches(text)) {
    final bban = m.group(0)!.substring(4).replaceAll(' ', '');
    final digits = bban.replaceAll(RegExp('[^0-9]'), '').length;
    if (bban.length >= 11 && bban.length <= 30 && digits >= 6) return true;
  }
  return false;
}

const _keyword =
    r'(?<![\p{L}\p{N}])'
    r'(?:passw(?:o|ö)rt(?:er|e)?|kennwort|password|passwd|passcode|'
    r'pin(?:-?code|-?nummer)?|puk|tan|api[-_ ]?key|secret|token|'
    r'zugangscode|zugangsdaten|geheimzahl)'
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

final _apiKey = RegExp(
  r'(?<![A-Za-z0-9])'
  r'(?:(?:sk|pk|rk|ghp|gho|xoxb|xoxp|tvly)[-_][A-Za-z0-9_-]{16,}'
  r'|AKIA[0-9A-Z]{16})',
);
