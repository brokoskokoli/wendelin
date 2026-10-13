/// Wendelin voice core (pure Dart): interfaces for trigger, microphone,
/// VAD, STT and TTS; endpointing; the voice pipeline state machine;
/// shortening answers for speech; TTS selection (K7); the speech model
/// catalog and downloader.
///
/// Platform implementations (sherpa-onnx, system TTS, recorder) live in the
/// app. Fakes are in `package:wendelin_voice/fakes.dart`, contract suites
/// in `package:wendelin_voice/testing.dart`.
library;

export 'src/io/audio_input.dart';
export 'src/io/speech_to_text.dart';
export 'src/io/text_to_speech.dart';
export 'src/io/trigger.dart';
export 'src/io/voice_activity_detector.dart';
export 'src/io/voice_exception.dart';
export 'src/models/model_downloader.dart';
export 'src/models/model_store.dart';
export 'src/models/speech_model.dart';
export 'src/models/speech_model_catalog.dart';
export 'src/pipeline/endpointer.dart';
export 'src/pipeline/voice_events.dart';
export 'src/pipeline/voice_pipeline.dart';
export 'src/text/spoken_answer.dart';
export 'src/text/voice_texts.dart';
export 'src/text/yes_no.dart';
export 'src/tts/speech_queue.dart';
export 'src/tts/tts_selector.dart';
