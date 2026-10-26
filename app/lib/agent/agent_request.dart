import 'package:wendelin_core/wendelin_core.dart';

import '../di/provider_config.dart';

/// The request the agent runs for [input]: the trimmed [text] and the
/// language of the interface, everything else as the user gave it.
UserInput requestFor(UserInput input, String text, String interfaceLanguage) =>
    UserInput(
      text: text,
      images: input.images,
      source: input.source,
      sttConfidence: input.sttConfidence,
      language: input.language,
      interfaceLanguage: interfaceLanguage,
      requestEscalation: input.requestEscalation,
    );

/// Whether [input] is routed privately (a `privacy` rule matches).
bool isPrivateRequest(ProviderConfig? config, UserInput input) {
  if (config == null) return false;
  try {
    return config.resolver().resolve(input).privacyFloor != null;
  } on Object {
    return false;
  }
}
