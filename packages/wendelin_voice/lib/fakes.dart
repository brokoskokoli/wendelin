/// Fakes for the voice interfaces: [FakeAudioInput], [AudioFrames],
/// [FakeVoiceActivityDetector], [FakeSpeechToText], [FakeTextToSpeech],
/// [FakeTriggerSource], [FakeBargeInDetector], [FakeModelStore], [FakeSpeechModelService]. Does not
/// depend on `package:test` (usable in the app's demo mode).
library;

export 'testing/fake_audio.dart';
export 'testing/fake_barge_in.dart';
export 'testing/fake_model_store.dart';
export 'testing/fake_speech.dart';
export 'testing/fake_speech_model_service.dart';
