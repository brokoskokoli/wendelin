// WP142: Umgebungshinweis vor dem Start und Tipp nach zweimal „zu leise“.

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/settings/wake/wake_enroll_screen.dart';

import '../support/wake_support.dart';
import 'wake_goldens_test.dart' show HangingAudio;
import 'wake_word_screen_test.dart' show pumpWake, until, wakeEnv;

const _screen = WakeEnrollScreen(speakerId: 'a', name: 'Anna');
final _hint = find.textContaining('Ruhiger Raum, normal laut sprechen');
final _tip = find.textContaining('Mehrmals nichts oder zu leise gehört');

void main() {
  testWidgets('Hinweis steht vor der ersten Aufnahme', (tester) async {
    await pumpWake(tester, wakeEnv(audio: HangingAudio([])), _screen);
    await until(tester, _hint);
    expect(_tip, findsNothing);
  });

  testWidgets('Hinweis ist nach der ersten Aufnahme weg', (tester) async {
    final env = wakeEnv(audio: HangingAudio([recording()]));
    await pumpWake(tester, env, _screen);
    await until(tester, find.text('1 von 15'));
    expect(_hint, findsNothing);
  });

  testWidgets('Kein Tipp nach einer leisen Aufnahme', (tester) async {
    final env = wakeEnv(audio: HangingAudio([recording(amplitude: 200)]));
    await pumpWake(tester, env, _screen);
    await until(tester, find.text('1 abgelehnt'));
    expect(_tip, findsNothing);
  });

  testWidgets('Tipp erscheint nach zwei leisen Aufnahmen in Folge', (
    tester,
  ) async {
    final env = wakeEnv(
      audio: HangingAudio([
        recording(amplitude: 200),
        recording(amplitude: 200),
      ]),
    );
    await pumpWake(tester, env, _screen);
    await until(tester, _tip);
    expect(find.text('2 abgelehnt'), findsOneWidget);
  });

  testWidgets('Der Tipp verschwindet nach einer angenommenen Aufnahme', (
    tester,
  ) async {
    final env = wakeEnv(
      audio: HangingAudio([
        recording(amplitude: 200),
        recording(amplitude: 200),
        recording(),
      ]),
    );
    await pumpWake(tester, env, _screen);
    await until(tester, find.text('1 von 15'));
    expect(_tip, findsNothing);
  });
}
