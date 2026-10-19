// WP85: spoken confirmation of an SMS or call is strict: a „ja“ with more
// words („Ja, aber an Ben“) does not send.
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

ToolQuestion _sms() => ToolQuestion(
  ConfirmationRequired(
    call: const ToolCallBlock(
      id: 'c',
      name: 'sms__compose',
      argumentsJson: '{"to":"0170 1234567","text":"Hi"}',
    ),
    description: 'SMS an Anna (01701234567)\nHi',
    respond: (_) {},
  ),
  request: 'Schreib Anna',
);

void main() {
  test('SMS-Bestätigung ist streng; „Ja, aber an Ben“ sendet nicht', () {
    expect(strictAnswer(_sms()), isTrue);
    YesNo? parse(String t) => VoiceController.recognizer.parse(
      t,
      strict: strictAnswer(_sms()),
      extraYes: YesNoRecognizer.smsYesWords,
    );
    expect(parse('Ja, aber an Ben'), isNull);
    expect(parse('ja bitte, schick es an Ben'), isNull);
    expect(parse('ja'), YesNo.yes);
    expect(parse('absenden'), YesNo.yes);
    expect(parse('nein'), YesNo.no);
  });
}
