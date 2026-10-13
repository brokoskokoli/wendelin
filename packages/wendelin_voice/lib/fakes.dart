/// Fakes for the voice interfaces: [FakeAudioInput], [AudioFrames],
/// [FakeVoiceActivityDetector], [FakeSpeechToText], [FakeTextToSpeech],
/// [FakeTriggerSource], [FakeModelStore]. Does not depend on
/// `package:test` (usable in the app's demo mode).
library;

export 'testing/fake_audio.dart';
export 'testing/fake_model_store.dart';
export 'testing/fake_speech.dart';
