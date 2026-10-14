import 'package:test/test.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  group('followUpUseful', () {
    test('Antwort endet mit einer Frage: sinnvoll', () {
      expect(followUpUseful(lastSentence: 'Soll ich das eintragen?'), isTrue);
      expect(followUpUseful(lastSentence: '  Und morgen?  '), isTrue);
    });

    test('Aussage ohne Rückfrage und ohne erneute Anfrage: nicht sinnvoll', () {
      expect(followUpUseful(lastSentence: 'Es ist 14 Uhr.'), isFalse);
      expect(followUpUseful(), isFalse);
      expect(followUpUseful(lastSentence: 'Wer? Egal.'), isFalse);
    });

    test(
      'genau 2:00 zwischen den Antwortenden: noch sinnvoll, danach nicht',
      () {
        expect(
          followUpUseful(
            lastSentence: 'Fertig.',
            sinceLastAnswer: const Duration(minutes: 2),
          ),
          isTrue,
        );
        expect(
          followUpUseful(
            lastSentence: 'Fertig.',
            sinceLastAnswer: const Duration(minutes: 2, microseconds: 1),
          ),
          isFalse,
        );
      },
    );

    test('zweite Sprachanfrage kurz nach der Antwort: sinnvoll', () {
      expect(
        followUpUseful(
          lastSentence: 'Fertig.',
          sinceLastAnswer: const Duration(seconds: 40),
        ),
        isTrue,
      );
      expect(
        followUpUseful(
          lastSentence: 'Fertig.',
          sinceLastAnswer: const Duration(minutes: 5),
        ),
        isFalse,
      );
    });
  });
}
