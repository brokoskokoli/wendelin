// WP113 (K84): LazyBargeVerifier haelt den vorgelesenen Text des
// Kandidaten-Moments, nicht den am Ende des Modell-Ladens.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/voice/wake/lazy_barge_verifier.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  test('spoken wird vor dem Laden des Erkenners gelesen', () async {
    var spoken = 'Am Bahnhof Stopp und weiter.';
    final load = Completer<SpeechToText>();
    final v = LazyBargeVerifier(
      stt: () => load.future,
      language: () => 'de',
      spokenText: () => spoken,
    );
    final result = v.verify(Int16List(16000), candidate: BargeInKeyword.stop);
    // Der Ring rutscht weiter, waehrend das Modell laedt.
    spoken = 'Ganz anderer Satz.';
    load.complete(FixedTranscriptStt('Stopp'));
    final verdict = await result;
    expect(verdict.result, 'echo');
    expect(verdict.keyword, isNull);
  });
}
