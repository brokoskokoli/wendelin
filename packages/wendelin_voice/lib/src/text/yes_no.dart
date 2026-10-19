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
/// - [YesNo.yes] needs yes markers and no no markers, [YesNo.no] needs no
///   markers and no yes markers; both or none give `null` (tap).
/// - Weak yes words ([weakYesWords]: „mach“, „klar“, „richtig“, „passt“)
///   count only when the whole answer is yes words and polite fillers
///   („Klar!“, „Passt, bitte“) – „Klar ist das falsch“ is not a yes.
/// - Hesitation („warte“, „Moment“, „wait“, „attends“, „na ja“, „später“,
///   „aber“) never yields a yes: with a no marker it stays „no“, otherwise
///   `null`.
/// - Negations („nicht“, „pas“, „not“) and stop words count as „no“.
/// - Empty transcripts or more than [maxWords] words give `null`.
/// - With `strict` (external tools, escalation below the privacy level)
///   a yes must be 1–2 words consisting only of yes words or one yes
///   phrase („Ja“, „Ja genau“, „Oui“, „Bien sûr“, „Go ahead“); „no“ is
///   recognized as usual.
final class YesNoRecognizer {
  /// Creates the recognizer.
  const YesNoRecognizer({this.maxWords = 8});

  /// Longer transcripts are not taken as an answer (it was probably a new
  /// request or side talk).
  final int maxWords;

  /// Single words meaning „yes“ (lower case, apostrophes removed).
  static const yesWords = {
    // de
    'ja', 'jawohl', 'jo', 'jep', 'jup', 'genau', 'gerne', 'gern',
    'einverstanden', 'ok', 'okay', 'okey',
    // fr
    'oui', 'ouais', 'daccord', 'certainement', 'volontiers',
    // en
    'yes', 'yeah', 'yep', 'yup', 'sure', 'correct', 'affirmative',
  };

  /// Words that mean „yes“ only when the answer consists of yes words and
  /// [politeWords] alone.
  static const weakYesWords = {'mach', 'machs', 'klar', 'richtig', 'passt'};

  /// Polite fillers allowed next to weak yes words.
  static const politeWords = {
    'bitte',
    'please',
    'sil',
    'vous',
    'te',
    'plaît',
    'plait',
    'merci',
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
    'falsch',
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

  /// Words of hesitation: never a yes.
  static const hesitationWords = {
    // de
    'warte', 'wart', 'warten', 'moment', 'momentchen', 'sekunde', 'später',
    'spaeter', 'pause', 'aber', 'naja', 'vielleicht', 'eventuell',
    // fr
    'attends', 'attendez', 'attend', 'mais', 'minute', 'peut', 'tard',
    // en
    'wait', 'hold', 'hang', 'later', 'but', 'maybe', 'perhaps', 'second',
  };

  /// Phrases of hesitation.
  static const hesitationPhrases = {'na ja', 'na gut', 'plus tard'};

  /// Verbs that answer „Soll ich sie absenden?“ with yes. Only passed for
  /// that question (`parse(extraYes: …)`): „send“ elsewhere is not a yes,
  /// and „anrufen“ does not confirm an SMS.
  static const smsYesWords = {
    // de
    'absenden', 'senden', 'abschicken', 'schicken',
    // fr
    'envoie', 'envoyer',
    // en
    'send',
  };

  /// Verbs that answer „Soll ich anrufen?“ with yes (see [smsYesWords]).
  static const callYesWords = {
    'anrufen', // de
    'appelle', 'appeler', // fr
    'call', // en
  };

  /// The answer in [transcript], or `null` if it is not a clear yes or no.
  /// [strict]: see the class documentation. [extraYes]: further single
  /// words that count like yes words for this question.
  YesNo? parse(
    String transcript, {
    bool strict = false,
    Set<String> extraYes = const {},
  }) {
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

    final hesitant =
        words.any(hesitationWords.contains) || hasPhrase(hesitationPhrases);
    final no = words.any(noWords.contains) || hasPhrase(noPhrases);
    bool isYes(String w) => yesWords.contains(w) || extraYes.contains(w);
    final weakOnly = words.every(
      (w) => isYes(w) || weakYesWords.contains(w) || politeWords.contains(w),
    );
    final yes =
        !hesitant &&
        (words.any(isYes) ||
            (weakOnly && words.any(weakYesWords.contains)) ||
            hasPhrase(yesPhrases, negatable: true));
    if (no && !yes) return YesNo.no;
    if (!yes || no) return null;
    if (strict && !_strictYes(words, extraYes)) return null;
    return YesNo.yes;
  }

  /// 1–2 words, only yes words, or exactly one yes phrase.
  static bool _strictYes(List<String> words, Set<String> extraYes) {
    if (words.length > 2) return false;
    if (words.every((w) => yesWords.contains(w) || extraYes.contains(w))) {
      return true;
    }
    if (words.length == 1 && weakYesWords.contains(words.single)) return true;
    return yesPhrases.contains(words.join(' '));
  }
}
