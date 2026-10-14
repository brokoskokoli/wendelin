/// Test support for the voice interfaces: everything from `fakes.dart`
/// plus the contract suites every implementation must pass
/// (`audioInputContract`, `voiceActivityDetectorContract`,
/// `speechToTextContract`, `textToSpeechContract`, `modelStoreContract`,
/// `bargeInDetectorContract`).
///
/// Depends on `package:test`; import it only from tests.
library;

export 'fakes.dart';
export 'testing/model_store_contract.dart';
export 'testing/voice_contracts.dart';
