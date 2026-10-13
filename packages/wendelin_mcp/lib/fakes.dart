/// Fakes for code built on `wendelin_mcp`: [FakeMcpSecrets],
/// [FakeAuthorizationBrowser], [InMemoryMcpCacheStore].
///
/// Does **not** depend on `package:test`. Tests import `testing.dart`,
/// which also exports the `FakeMcpServer` and `mcpClientContract`.
library;

import 'testing/fakes.dart';

export 'testing/fakes.dart';
