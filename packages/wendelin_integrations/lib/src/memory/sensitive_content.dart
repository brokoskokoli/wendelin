// Schutzregel des Gedächtnisses: Zugangsdaten, Karten- und Kontonummern
// werden nie gespeichert (Konzept „Gedächtnis im Detail“). Eine eigene,
// ähnliche (nicht identische) Prüfung hat `MemoryRepository` in
// wendelin_storage; beide sollen später in eine gemeinsame Quelle in
// wendelin_core wandern (Folgepaket). Bis dahin prüft das Tool hiermit vor
// dem Port, und der Port wendet seine eigene Regel an.

final _digitRun = RegExp(r'\d(?:[ -]?\d){12,18}');

final _iban = RegExp(
  r'\b[A-Z]{2}\d{2}(?:[ ]?[A-Z0-9]{4}){2,7}(?:[ ]?[A-Z0-9]{1,4})?\b',
  caseSensitive: false,
);

final _credential = RegExp(
  r'\b(passwort|password|passwd|kennwort|pin|puk|tan|api[-_ ]?key|'
  r'zugangsdaten|zugangscode|secret|token)\b'
  r'[^\n.]{0,20}?(?:\bist\b|\bis\b|\blautet\b|[:=])\s*\S+',
  caseSensitive: false,
);

final _apiKey = RegExp(
  r'\b(?:sk|pk|rk|ghp|gho|xoxb|xoxp|tvly|AKIA)[-_]?[A-Za-z0-9_-]{16,}',
);

/// Why [text] must not be stored in memory, or `null` if it is fine.
///
/// Detects Luhn-valid card numbers (13–19 digits, spaces/dashes allowed),
/// IBAN-like account numbers, „Passwort/PIN/… ist|: …“ and API-key-like
/// tokens. Health and financial topics are not detected by keywords (too
/// unreliable); they are only saved on the user's explicit request.
String? sensitiveContentReason(String text) {
  for (final m in _digitRun.allMatches(text)) {
    final digits = m[0]!.replaceAll(RegExp('[ -]'), '');
    if (_luhnValid(digits)) {
      return 'Kartennummern werden nicht gespeichert.';
    }
  }
  if (_iban.hasMatch(text)) {
    return 'Kontonummern (IBAN) werden nicht gespeichert.';
  }
  if (_credential.hasMatch(text) || _apiKey.hasMatch(text)) {
    return 'Passwörter, PINs und Zugangsdaten werden nicht gespeichert.';
  }
  return null;
}

bool _luhnValid(String digits) {
  if (digits.length < 13 || digits.length > 19) return false;
  var sum = 0;
  for (var i = 0; i < digits.length; i++) {
    var d = digits.codeUnitAt(digits.length - 1 - i) - 0x30;
    if (i.isOdd) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
  }
  return sum % 10 == 0;
}
