// WP85 (K49): spoken confirmation before an SMS or a call. „ja“ and the
// matching verb run it, „nein“ / „abbrechen“ do not; an unclear answer runs
// nothing and asks again; nothing is sent in conversation mode or locked
// without a clear answer.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/di/sms_drafts.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import 'confirm_by_voice_test.dart' show FlakyAudioInput, ScriptedTts;
import 'voice_controller_test.dart' show utterance, waitVoice;

const _smsArgs = '{"to":"+49 170 1234567","text":"Ich komme später"}';
const _callArgs = '{"to":"0171 111"}';
const _smsQuestion =
    'Nachricht an Anna Meier: Ich komme später. Soll ich sie absenden?';
const _callQuestion = 'Anruf bei Ben Schmidt. Soll ich anrufen?';
const _smsRepeat = 'Bitte sag „absenden“ oder „abbrechen“.';
const _callRepeat = 'Bitte sag „anrufen“ oder „abbrechen“.';

void main() {
  late TestEnv env;
  late ProviderContainer c;
  late void Function(String) savedSink;

  setUp(() {
    savedSink = voiceLogSink;
    voiceLogSink = (_) {};
    VoiceController.micStartTimeout = const Duration(milliseconds: 150);
    VoiceController.promptTimeout = const Duration(milliseconds: 200);
  });
  tearDown(() {
    voiceLogSink = savedSink;
    VoiceController.micStartTimeout = const Duration(seconds: 3);
    VoiceController.promptTimeout = const Duration(seconds: 15);
    c.dispose();
  });

  VoiceController voice() => c.read(voiceControllerProvider.notifier);

  /// „Schreib Anna …“ / „Ruf Ben an“ by voice; [answers] are the transcripts
  /// of the recordings after the question.
  Future<void> ask({
    required String tool,
    required String args,
    required List<String> answers,
    required ScriptedTts tts,
    bool conversationMode = false,
  }) async {
    env = TestEnv(
      enabled: const {'contacts'},
      providerConfig: scripted(
        FakeLlmProvider([
          ScriptedTurn.toolCalls([call('c1', tool, args)]),
          ScriptedTurn.text('Erledigt.'),
        ]),
      ),
      extraOverrides: [
        activeVoiceProvider.overrideWith(
          (ref) async => VoiceComponents(
            audio: FlakyAudioInput(FakeAudioInput(frames: utterance())),
            vad: FakeVoiceActivityDetector(),
            stt: FakeSpeechToText([
              const Transcript(text: 'Mach das'),
              for (final a in answers) Transcript(text: a),
            ]),
            textToSpeech: (_) async => tts,
            config: VoicePipelineConfig(conversationMode: conversationMode),
          ),
        ),
      ],
    );
    c = env.container();
    expect(await voice().start(TriggerKind.pushToTalk), isTrue);
  }

  Future<void> sms(
    List<String> answers,
    ScriptedTts tts, {
    bool conversationMode = false,
  }) => ask(
    tool: 'sms__compose',
    args: _smsArgs,
    answers: answers,
    tts: tts,
    conversationMode: conversationMode,
  );

  Future<void> phoneCall(List<String> answers, ScriptedTts tts) =>
      ask(tool: 'phone__call', args: _callArgs, answers: answers, tts: tts);

  /// The question was read, the answer ended the request.
  Future<void> done() async {
    await voice().whenIdle;
    expect(c.read(agentControllerProvider).pending, isNull);
  }

  for (final yes in ['Ja', 'Absenden', 'Ja, absenden', 'Senden']) {
    test('SMS: „$yes“ sendet den vorgelesenen Text', () async {
      final tts = ScriptedTts();
      await sms([yes], tts);
      await done();
      expect(tts.spoken, contains(_smsQuestion));
      expect(env.phone.sent, [
        (number: '+491701234567', text: 'Ich komme später'),
      ]);
    });
  }

  for (final no in ['Nein', 'Abbrechen']) {
    test('SMS: „$no“ sendet nichts', () async {
      final tts = ScriptedTts();
      await sms([no], tts);
      await done();
      expect(tts.spoken, contains(_smsQuestion));
      expect(env.phone.sent, isEmpty);
    });
  }

  test('SMS: unklar, dann „absenden“: erst nach der klaren Antwort', () async {
    final tts = ScriptedTts();
    await sms(['Vielleicht', 'Absenden'], tts);
    await done();
    expect(tts.spoken, containsAllInOrder([_smsQuestion, _smsRepeat]));
    expect(env.phone.sent, hasLength(1));
  });

  test('SMS: zweimal unklar: nichts gesendet, Antwort nur per Tipp', () async {
    final tts = ScriptedTts();
    await sms(['Vielleicht', 'Hm, mal sehen'], tts);
    await waitVoice(c, (v) => v.tapOnly);
    expect(tts.spoken, contains(_smsRepeat));
    expect(env.phone.sent, isEmpty);
    expect(c.read(agentControllerProvider).pending!.answered, isFalse);
    c.read(agentControllerProvider.notifier).answer(approved: false);
    await voice().whenIdle;
    expect(env.phone.sent, isEmpty);
  });

  test('SMS: „nicht absenden“ ist nicht eindeutig: nichts gesendet', () async {
    final tts = ScriptedTts();
    await sms(['Nicht absenden', 'Nicht absenden'], tts);
    await waitVoice(c, (v) => v.tapOnly);
    expect(env.phone.sent, isEmpty);
    c.read(agentControllerProvider.notifier).answer(approved: false);
    await voice().whenIdle;
    expect(env.phone.sent, isEmpty);
  });

  test('SMS: „anrufen“ bestätigt keine SMS', () async {
    final tts = ScriptedTts();
    await sms(['Anrufen', 'Anrufen'], tts);
    await waitVoice(c, (v) => v.tapOnly);
    expect(env.phone.sent, isEmpty);
    expect(env.phone.called, isEmpty);
    c.read(agentControllerProvider.notifier).answer(approved: false);
    await voice().whenIdle;
  });

  test('SMS: im Gesprächsmodus „Ja“ sendet, Unklares nicht', () async {
    final tts = ScriptedTts();
    await sms(['Ja'], tts, conversationMode: true);
    await done();
    expect(env.phone.sent, hasLength(1));

    final unclear = ScriptedTts();
    c.dispose();
    await sms(['Vielleicht', 'Mal sehen'], unclear, conversationMode: true);
    await waitVoice(c, (v) => v.tapOnly);
    expect(env.phone.sent, isEmpty);
    c.read(agentControllerProvider.notifier).answer(approved: false);
    await voice().whenIdle;
    expect(env.phone.sent, isEmpty);
  });

  test('SMS: nach Änderung des Textes bestätigt „Ja“ nicht', () async {
    final tts = ScriptedTts();
    // The user edits the text in the preview while the question is read.
    await sms(['Ja'], tts);
    c
        .read(smsDraftEditsProvider)
        .set('+491701234567', 'Ich komme später', 'Ich komme gar nicht');
    await waitVoice(c, (v) => v.tapOnly);
    expect(env.phone.sent, isEmpty);
    c.read(agentControllerProvider.notifier).answer(approved: false);
    await voice().whenIdle;
    expect(env.phone.sent, isEmpty);
  });

  for (final yes in ['Ja', 'Anrufen', 'Ja, anrufen']) {
    test('Anruf: „$yes“ ruft an', () async {
      final tts = ScriptedTts();
      await phoneCall([yes], tts);
      await done();
      expect(tts.spoken, contains(_callQuestion));
      expect(env.phone.called, ['0171111']);
    });
  }

  for (final no in ['Nein', 'Abbrechen']) {
    test('Anruf: „$no“ ruft nicht an', () async {
      final tts = ScriptedTts();
      await phoneCall([no], tts);
      await done();
      expect(env.phone.called, isEmpty);
      expect(env.phone.dialed, isEmpty);
    });
  }

  test('Anruf: unklar, dann „anrufen“', () async {
    final tts = ScriptedTts();
    await phoneCall(['Vielleicht', 'Anrufen'], tts);
    await done();
    expect(tts.spoken, containsAllInOrder([_callQuestion, _callRepeat]));
    expect(env.phone.called, ['0171111']);
  });

  test('Anruf: zweimal unklar oder „absenden“: nichts, nur Tipp', () async {
    final tts = ScriptedTts();
    await phoneCall(['Absenden', 'Hm'], tts);
    await waitVoice(c, (v) => v.tapOnly);
    expect(env.phone.called, isEmpty);
    c.read(agentControllerProvider.notifier).answer(approved: false);
    await voice().whenIdle;
    expect(env.phone.called, isEmpty);
  });

  group('gesperrtes Gerät', () {
    test('keine SMS und kein Anruf, das Modell läuft nicht', () async {
      final events = <String>[];
      for (final said in ['Schick Anna eine SMS', 'Ruf Ben an']) {
        var innerCalled = false;
        final refused = <String>[];
        final gate = LockGateAgentRun(
          inner: _Spy(() => innerCalled = true),
          locked: () => true,
          runCommand: (_, _) async => true,
          onRefused: refused.add,
          trigger: () => 'assistant',
        );
        final out = await gate
            .run(UserInput(text: said, language: 'de'))
            .toList();
        events.add(said);
        expect(innerCalled, isFalse);
        expect(refused, ['assistant']);
        expect(out.whereType<ConfirmationRequired>(), isEmpty);
      }
      expect(events, hasLength(2));
    });
  });
}

final class _Spy implements AgentRun {
  _Spy(this.onRun);
  final void Function() onRun;

  @override
  Stream<AgentEvent> run(UserInput input) {
    onRun();
    return const Stream.empty();
  }

  @override
  void cancel() {}
}
