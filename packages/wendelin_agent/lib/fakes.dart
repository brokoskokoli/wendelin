/// Simple implementations of the agent ports for tests, evals and the demo
/// mode: [FixedMemoryRetriever], [InMemoryConversation], [FixedBudgetGuard],
/// [FlatCostEstimator], and for routing [FakeToolCategoryMatcher] and
/// [FixedNetworkStatus]. Does not depend on `package:test`.
library;

export 'testing/fake_ports.dart';
export 'testing/fake_routing.dart';
