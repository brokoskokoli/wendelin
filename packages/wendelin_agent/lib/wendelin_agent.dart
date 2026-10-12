/// Wendelin agent loop: context building, provider resolution, limits,
/// escalation and sentence chunking for TTS. Depends only on
/// `wendelin_core` interfaces.
///
/// Simple implementations of the ports (for tests, evals and the demo mode)
/// are in `package:wendelin_agent/fakes.dart`.
library;

export 'src/agent_config.dart';
export 'src/agent_runner.dart';
export 'src/context_builder.dart';
export 'src/give_up_classifier.dart';
export 'src/ports.dart';
export 'src/provider_resolver.dart';
export 'src/sentence_chunker.dart';
