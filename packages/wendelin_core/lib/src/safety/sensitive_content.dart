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
///   alphanumerics. Written compactly or in groups of four separated by
///   spaces (last group 1–4) with at least 6 digits, it counts without the
///   mod-97 checksum if the BBAN has 15 or more characters, so mistyped
///   IBANs are rejected too; shorter BBANs and any other spacing (spaces or
///   dashes between arbitrary chunks) need a valid mod-97 checksum.
/// - **Credentials**: a keyword (Passwort, Kennwort, Password, Passwd,
///   Passcode, PIN, PIN-Code, PUK, API-Key, Zugangscode, Zugangsdaten,
///   Geheimzahl) followed, within up to four words, by `:`, `=`, "ist",
///   "lautet", "heißt", "war" or "is"/"was" and a value ("Das Passwort für
///   das WLAN ist …"), or followed directly by a value containing a digit
///   ("PIN 1234", "Passwort hunter2"). Everyday words (TAN, Secret, Token)
///   and card security codes (CVV, CVC, Sicherheitscode,
///   Kartenprüfnummer) count only with `:`/`=` or a value containing a
///   digit ("TAN ist 123456", "CVV 123"). Also API-key-like tokens (`sk-…`,
///   `pk_…`, `ghp_…`, `xoxb-…`, `tvly-…`, `AKIA…`).
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

/// [text] with every finding of [detectSensitiveContent] replaced by [mask]
/// (card number, IBAN, credential with its value, API key); the rest stays
/// readable. A credential is replaced from its keyword up to the end of its
/// clause (up to `.`, `!`, `?`, `;`, a line break or the end of the text:
/// "Mein Passwort ist hunter2. Danke" becomes "Mein *** Danke"). Everything that is
/// neither letter nor digit behind the keyword is skipped first,
/// so the first value character is always masked. Known limit: a value with
/// ". " inside releases the rest ("Dr. Who42" leaves "Who42"). Uses the same
/// detection rules as [detectSensitiveContent], which stays unchanged.
String redactSensitiveContent(String text, {String mask = '***'}) {
  final spans = <(int, int)>[
    ..._cardSpans(text),
    ..._ibanSpans(text),
    for (final m in _credential.allMatches(text))
      (m.start, _clauseEnd(text, _valueStart(text, m))),
    for (final m in _apiKey.allMatches(text)) (m.start, m.end),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final out = StringBuffer();
  var pos = 0;
  var i = 0;
  while (i < spans.length) {
    var (from, to) = spans[i++];
    while (i < spans.length && spans[i].$1 <= to) {
      if (spans[i].$2 > to) to = spans[i].$2;
      i++;
    }
    out
      ..write(text.substring(pos, from))
      ..write(mask);
    pos = to;
  }
  return out.toString() + text.substring(pos);
}

// Where the value begins: the value token of the match (`v1`/`v2` for the
// "keyword + value with a digit" forms) or else the match's last character
// (the first character after the separator). From there every character that
// is neither letter nor digit is skipped ("Passwort:. x", "PIN=! 1234",
// "ist... x", line breaks included), so the clause end is only searched
// behind at least one value character. "PIN 1234. Danke": the value token
// starts at "1", its trailing full stop ends the clause.
int _valueStart(String text, RegExpMatch m) {
  final v = m.namedGroup('v1') ?? m.namedGroup('v2');
  var e = v == null ? m.end - 1 : m.end - v.length;
  final alnum = RegExp(r'[\p{L}\p{N}]', unicode: true);
  while (e < text.length && !alnum.hasMatch(text[e])) {
    e++;
  }
  return e;
}

// End of the clause (scanned from [end]) that holds the credential value: up to a `.`, `!`, `?` or
// `;` followed by whitespace or the end, a line break, or the end of the text
// (spoken values come in several words: "PIN 12 34", "eins zwei drei vier").
// Better too much than too little.
int _clauseEnd(String text, int end) {
  for (var e = end; e < text.length; e++) {
    final c = text.codeUnitAt(e);
    if (c == 0x0A || c == 0x0D) return e;
    if (c == 0x2E || c == 0x21 || c == 0x3F || c == 0x3B) {
      if (e + 1 >= text.length || text.codeUnitAt(e + 1) <= 0x20) return e + 1;
    }
  }
  return text.length;
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

bool _containsCardNumber(String text) => _cardSpans(text).iterator.moveNext();

// Character ranges of the card numbers in [text] (see [detectSensitiveContent]).
Iterable<(int, int)> _cardSpans(String text) sync* {
  for (final m in _digitRun.allMatches(text)) {
    if (m.group(1) != null) continue;
    final run = m.group(0)!;
    final groups = run.split(_separator);
    final seps = _separator.allMatches(run).toList();
    for (var start = 0; start < groups.length; start++) {
      final first = groups[start].codeUnitAt(0);
      if (first < 0x32 || first > 0x36) continue; // '2'..'6'
      var digits = '';
      for (var end = start; end < groups.length; end++) {
        digits += groups[end];
        if (digits.length > 19) break;
        if (digits.length >= 13 && !_isPhone(digits) && luhnValid(digits)) {
          final from = start == 0 ? 0 : seps[start - 1].end;
          final to = end == groups.length - 1 ? run.length : seps[end].start;
          yield (m.start + from, m.start + to);
        }
      }
    }
  }
}

bool _isPhone(String digits) =>
    digits.length == 13 && (digits.startsWith('49') || digits.startsWith('43'));

// Compact or in groups of four separated by spaces: counts without mod-97
// (mistyped IBANs too) if the BBAN has at least 15 characters.
final _ibanCandidate = RegExp(
  r'(?<![A-Za-z0-9])[A-Za-z]{2}\d{2}'
  r'(?:[A-Za-z0-9]{11,30}|(?: +[A-Za-z0-9]{4}){2,7}(?: +[A-Za-z0-9]{1,4})?)'
  r'(?![A-Za-z0-9])',
);

final _ibanStart = RegExp(r'(?<![A-Za-z0-9])[A-Za-z]{2}\d{2}');
final _alnumRun = RegExp('[A-Za-z0-9]+');
final _nonDigit = RegExp('[^0-9]');

bool _containsIban(String text) => _ibanSpans(text).iterator.moveNext();

// Character ranges of the IBANs in [text] (see [detectSensitiveContent]).
Iterable<(int, int)> _ibanSpans(String text) sync* {
  for (final m in _ibanCandidate.allMatches(text)) {
    final iban = m.group(0)!.replaceAll(' ', '');
    final bban = iban.substring(4);
    if (bban.replaceAll(_nonDigit, '').length < 6) continue;
    if (bban.length >= 15 || ibanChecksumValid(iban)) yield (m.start, m.end);
  }
  // Any spacing (single spaces or dashes between arbitrary chunks): only
  // with a valid mod-97 checksum.
  for (final m in _ibanStart.allMatches(text)) {
    final iban = StringBuffer(m.group(0)!);
    var pos = m.end;
    while (true) {
      if (pos < text.length && (text[pos] == ' ' || text[pos] == '-')) {
        pos++;
      }
      final run = _alnumRun.matchAsPrefix(text, pos);
      if (run == null) break;
      iban.write(run.group(0));
      pos = run.end;
      final length = iban.length - 4;
      if (length > 30) break;
      if (length >= 11 && ibanChecksumValid(iban.toString())) {
        yield (m.start, pos);
        break;
      }
    }
  }
}

/// ISO 13616 mod-97 check of a compact IBAN (any case, no separators).
bool ibanChecksumValid(String iban) {
  final s = (iban.substring(4) + iban.substring(0, 4)).toUpperCase();
  var rest = 0;
  for (final c in s.codeUnits) {
    if (c >= 0x30 && c <= 0x39) {
      rest = (rest * 10 + c - 0x30) % 97;
    } else if (c >= 0x41 && c <= 0x5a) {
      rest = (rest * 100 + c - 0x41 + 10) % 97;
    } else {
      return false;
    }
  }
  return rest == 1;
}

// Strong keywords: any "ist/lautet/…" phrasing counts (conservative).
const _keyword =
    r'(?<![\p{L}\p{N}])'
    r'(?:passw(?:o|ö)rt(?:er|e)?|kennwort|password|passwd|passcode|'
    r'pin(?:-?code|-?nummer)?|puk|api[-_ ]?key|'
    r'zugangscode|zugangsdaten|geheimzahl)'
    r'(?![\p{L}\p{N}])';

// Weak keywords (also everyday words): only with `:`/`=` or a value
// containing a digit.
const _weakKeyword =
    r'(?<![\p{L}\p{N}])'
    r'(?:tan|secret|token|cvv|cvc|cvv2|sicherheitscode|kartenprüfnummer|'
    r'kartenpruefnummer|prüfnummer|pruefnummer|prüfziffer)'
    r'(?![\p{L}\p{N}])';

final _credential = RegExp(
  // Keyword, up to four words, then an assignment and a value.
  '$_keyword'
  r'(?:\s+[\p{L}\p{N}-]+){0,4}?'
  r'(?:\s*[:=]|\s+(?:ist|lautet|heißt|heisst|war|is|was)(?![\p{L}\p{N}]))'
  r'\s*\S'
  // Or keyword directly followed by a value containing a digit.
  '|$_keyword'
  r'\s*[:=]?\s+(?=[^\s]*\p{N})(?<v1>[^\s]+)'
  // Weak keyword, up to four words, `:`/`=` and any value.
  '|$_weakKeyword'
  r'(?:\s+[\p{L}\p{N}-]+){0,4}?\s*[:=]\s*\S'
  // Weak keyword (optionally "ist/lautet/is/was/war") and a value with a
  // digit.
  '|$_weakKeyword'
  r'(?:\s+(?:ist|lautet|is|was|war)(?![\p{L}\p{N}]))?'
  r'\s+(?=[^\s]*\p{N})(?<v2>[^\s]+)',
  caseSensitive: false,
  unicode: true,
);

final _apiKey = RegExp(
  r'(?<![A-Za-z0-9])'
  r'(?:(?:sk|pk|rk|ghp|gho|xoxb|xoxp|tvly)[-_][A-Za-z0-9_-]{16,}'
  r'|AKIA[0-9A-Z]{16})',
);
