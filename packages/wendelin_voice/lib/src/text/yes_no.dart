/// Answer to a confirmation question.
enum YesNo {
  /// Approved („ja“, „oui“, „yes“).
  yes,

  /// Declined („nein“, „non“, „no“, also „Stopp“).
  no,
}

/// Recognizes a spoken „ja“/„nein“ answer to a confirmation question in
/// German, French and English (concept: Bestätigungen per Stimme).
///
/// Rules (conservative: a wrong „yes“ is the dangerous mistake):
/// - Case, punctuation and apostrophes are ignored („d'accord“ →
///   `daccord`, „don't“ → `dont`).
/// - The answer is [YesNo.yes] if it contains yes markers and no no
///   markers, [YesNo.no] if it contains no markers and no yes markers.
/// - Both kinds („ja, nicht löschen“), none („vielleicht“), an empty
///   transcript or more than [maxWords] words give `null` – the user then
///   answers by tap.
/// - Negations („nicht“, „pas“, „not“) and stop words count as „no“.
final class YesNoRecognizer {
  /// Creates the recognizer.
  const YesNoRecognizer({this.maxWords = 8});

  /// Longer transcripts are not taken as an answer (it was probably a new
  /// request or side talk).
  final int maxWords;

  /// Single words meaning „yes“ (lower case, apostrophes removed).
  static const yesWords = {
    // de
    'ja', 'jawohl', 'jo', 'jep', 'jup', 'genau', 'klar', 'gerne', 'gern',
    'einverstanden', 'richtig', 'passt', 'mach', 'machs', 'ok', 'okay',
    'okey',
    // fr
    'oui', 'ouais', 'daccord', 'certainement', 'volontiers',
    // en
    'yes', 'yeah', 'yep', 'yup', 'sure', 'correct', 'affirmative',
  };

  /// Multi-word phrases meaning „yes“ (words separated by single spaces).
  static const yesPhrases = {
    // de
    'in ordnung', 'na klar', 'mach das', 'mach es', 'tu das',
    // fr
    'bien sûr', 'bien sur', 'vas y', 'allez y', 'cest bon', 'je confirme',
    // en
    'go ahead', 'do it', 'of course', 'all right', 'alright',
  };

  /// Single words meaning „no“ (including negations and stop words).
  static const noWords = {
    // de
    'nein', 'nee', 'nö', 'noe', 'ne', 'nicht', 'nichts', 'kein', 'keine',
    'niemals', 'abbrechen', 'abbruch', 'stopp', 'stop', 'halt', 'lass',
    // fr
    'non', 'pas', 'jamais', 'annule', 'annuler', 'arrête', 'arrete',
    // en
    'no', 'nope', 'nah', 'not', 'dont', 'never', 'cancel', 'negative',
  };

  /// Negations; a yes phrase right after one does not count.
  static const negations = {'nicht', 'not', 'dont', 'pas', 'ne', 'kein'};

  /// Multi-word phrases meaning „no“.
  static const noPhrases = {
    // de
    'lieber nicht', 'auf keinen fall', 'lass es', 'lass das',
    // fr
    'laisse tomber', 'pas du tout',
    // en
    'no way', 'leave it',
  };

  /// The answer in [transcript], or `null` if it is not a clear yes or no.
  YesNo? parse(String transcript) {
    final words = transcript
        .toLowerCase()
        .replaceAll(RegExp('[\'’`´]'), '')
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty || words.length > maxWords) return null;
    // A phrase right after a negation does not count („don't do it“).
    bool hasPhrase(Set<String> phrases, {bool negatable = false}) {
      for (final phrase in phrases) {
        final p = phrase.split(' ');
        for (var i = 0; i + p.length <= words.length; i++) {
          var match = true;
          for (var k = 0; k < p.length && match; k++) {
            match = words[i + k] == p[k];
          }
          if (match &&
              !(negatable && i > 0 && negations.contains(words[i - 1]))) {
            return true;
          }
        }
      }
      return false;
    }

    final yes =
        words.any(yesWords.contains) || hasPhrase(yesPhrases, negatable: true);
    final no = words.any(noWords.contains) || hasPhrase(noPhrases);
    if (yes == no) return null;
    return yes ? YesNo.yes : YesNo.no;
  }
}
