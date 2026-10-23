import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/voice/model_check.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  const model = SpeechModelCatalog.parakeetV3;
  late FakeSpeechModelService service;
  setUp(() => service = FakeSpeechModelService());

  test('installiert: wahr', () async {
    service.installed.add(model.id);
    expect(await isModelInstalled(service, model), isTrue);
  });

  test('nichts da: falsch, kein Fehler', () async {
    expect(await isModelInstalled(service, model), isFalse);
  });

  test('beschädigt: modelBroken', () async {
    service.damaged.add(model.id);
    await expectLater(
      isModelInstalled(service, model),
      throwsA(
        isA<VoiceException>().having(
          (e) => e.kind,
          'kind',
          VoiceErrorKind.modelBroken,
        ),
      ),
    );
  });
}
