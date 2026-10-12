/// Test support for code built on `wendelin_core`: everything from
/// `fakes.dart` plus the reusable contract suites (`llmProviderContract`,
/// `toolInvokerContract`).
///
/// Depends on `package:test`; import it only from tests. Production code
/// (e.g. the app's demo mode) imports `package:wendelin_core/fakes.dart`.
library;

export 'fakes.dart';
export 'testing/llm_provider_contract.dart';
export 'testing/tool_invoker_contract.dart';
