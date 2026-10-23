import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/voice/confirm_prompts.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  test('strenge Antwort: erkannte Sprache en in de-App wird zur sicheren Menge', () {
    expect(answerLanguage(strict: true, spoken: 'en', app: 'de'), isNull);
    expect(answerLanguage(strict: true, spoken: 'de', app: 'de'), 'de');
    expect(answerLanguage(strict: true, spoken: null, app: 'de'), 'de');
    expect(answerLanguage(strict: true, spoken: 'en-US', app: 'en'), 'en');
    expect(answerLanguage(strict: false, spoken: 'en', app: 'de'), 'en');
    expect(answerLanguage(strict: false, spoken: null, app: 'de'), 'de');
  });

  test('Yeah/Okay bestätigt eine externe Aktion in der de-App nicht', () {
    const r = YesNoRecognizer();
    YesNo? parse(String t, String? lang) =>
        r.parse(t, strict: true, language: lang);
    final lang = answerLanguage(strict: true, spoken: 'en', app: 'de');
    expect(parse('Yeah', lang), isNull);
    expect(parse('Okay', lang), isNull);
    expect(parse('Ja', lang), YesNo.yes);
    // Same in an English app with English speech.
    final en = answerLanguage(strict: true, spoken: 'en', app: 'en');
    expect(parse('Yeah', en), YesNo.yes);
  });
}
