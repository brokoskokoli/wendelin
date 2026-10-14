import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/voice/wake/utterance_capture.dart';

import '../../support/wake_support.dart';

Utterance? run(UtteranceCapture c, List<Int16List> frames) {
  for (final f in frames) {
    final r = c.feed(f);
    if (r != null) return r;
  }
  return null;
}

void main() {
  test('Wort mit Stille davor und danach wird angenommen', () {
    final r = run(UtteranceCapture(), recording())!;
    expect(r.verdict, UtteranceVerdict.accepted);
    // 900 ms Sprache plus Vorlauf und etwas Nachlauf.
    expect(r.pcm!.length, inInclusiveRange(16 * 900, 16 * 1700));
    expect(r.speechEnd, inInclusiveRange(16 * 900, r.pcm!.length));
  });

  test('zu leise: Pegel unter der Grenze', () {
    final r = run(UtteranceCapture(), recording(amplitude: 350))!;
    expect(r.verdict, UtteranceVerdict.tooQuiet);
    expect(r.pcm, isNull);
  });

  test('abgeschnitten: Sprache schon in den ersten 300 ms', () {
    final r = run(UtteranceCapture(), recording(lead: 0))!;
    expect(r.verdict, UtteranceVerdict.cutOff);
  });

  test('nichts gesprochen: nach 6 s ohne Sprache', () {
    final r = run(UtteranceCapture(), recording(speech: 0, tail: 7000))!;
    expect(r.verdict, UtteranceVerdict.noSpeech);
  });

  test('ein Klick ist keine Sprache', () {
    final r = run(UtteranceCapture(), recording(speech: 60, tail: 800))!;
    expect(r.verdict, UtteranceVerdict.noSpeech);
  });

  test('zu lang: Dauersprache wird nach 2,5 s verworfen', () {
    final r = run(UtteranceCapture(), recording(speech: 4000))!;
    expect(r.verdict, UtteranceVerdict.tooLong);
  });

  test('Ergebnis bleibt stehen, level folgt dem Pegel', () {
    final c = UtteranceCapture();
    final first = run(c, recording())!;
    expect(c.feed(Int16List(320)), same(first));
    final quiet = UtteranceCapture()..feed(Int16List(320));
    expect(quiet.level, 0);
  });
}
