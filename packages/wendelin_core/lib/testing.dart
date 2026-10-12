/// Test support for code built on `wendelin_core`: scripted provider, fake
/// tools/integrations and the reusable `LlmProvider` contract suite.
///
/// Depends on `package:test`; import it only from tests (and the app's demo
/// mode for [FakeLlmProvider]).
library;

export 'testing/fake_llm_provider.dart';
export 'testing/fake_tools.dart';
export 'testing/llm_provider_contract.dart';
