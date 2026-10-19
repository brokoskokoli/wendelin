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
export 'src/io/barge_in_detector.dart';
export 'src/io/speech_to_text.dart';
export 'src/io/text_to_speech.dart';
export 'src/io/trigger.dart';
export 'src/io/voice_activity_detector.dart';
export 'src/io/voice_exception.dart';
export 'src/models/model_downloader.dart';
export 'src/models/model_install_states.dart';
export 'src/models/model_retention.dart';
export 'src/models/model_store.dart';
export 'src/models/speech_model.dart';
export 'src/models/speech_model_catalog.dart';
export 'src/models/speech_model_service.dart';
export 'src/models/voice_settings.dart';
export 'src/pipeline/conversation_offer.dart';
export 'src/pipeline/endpointer.dart';
export 'src/pipeline/voice_events.dart';
export 'src/pipeline/voice_pipeline.dart';
export 'src/recognizer/bpe_encoder.dart';
export 'src/recognizer/hint_terms.dart';
export 'src/recognizer/hotwords.dart';
export 'src/recognizer/recognition_session.dart';
export 'src/speaker/speaker_embedder.dart';
export 'src/speaker/speaker_identifier.dart';
export 'src/speaker/speaker_match.dart';
export 'src/speaker/speaker_profile.dart';
export 'src/speaker/speaker_profile_store.dart';
export 'src/text/locked_command.dart';
export 'src/text/spoken_answer.dart';
export 'src/text/vocabulary.dart';
export 'src/text/voice_texts.dart';
export 'src/text/yes_no.dart';
export 'src/tts/speech_queue.dart';
export 'src/tts/tts_selector.dart';
export 'src/wake/candidate_wake_engine.dart';
export 'src/wake/keyword_spec.dart';
export 'src/wake/pre_roll_buffer.dart';
export 'src/wake/pre_roll_speech.dart';
export 'src/wake/speech_gate.dart';
export 'src/wake/wake_calibration.dart';
export 'src/wake/wake_feature_extractor.dart';
export 'src/wake/wake_math.dart';
export 'src/wake/wake_templates.dart';
export 'src/wake/wake_verifier.dart';
export 'src/wake/wake_word_barge_in.dart';
export 'src/wake/wake_word_engine.dart';
export 'src/wake/wake_word_listener.dart';
export 'src/wake/wake_word_trigger.dart';
