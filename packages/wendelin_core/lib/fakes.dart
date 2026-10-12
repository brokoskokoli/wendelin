/// Fakes for code built on `wendelin_core`: scripted [FakeLlmProvider],
/// [FakeTool], [FakeIntegration], [FakeToolCatalog], [FakeToolInvoker].
///
/// Does **not** depend on `package:test`, so the app may use it in
/// production code (demo mode). Tests import `testing.dart`, which also
/// exports the contract suites.
library;

export 'testing/fake_llm_provider.dart';
export 'testing/fake_tools.dart';
