/// Test support for `wendelin_mcp`: everything from `fakes.dart`, the
/// in-process [FakeMcpServer] (Streamable HTTP and Legacy-SSE, bearer and
/// OAuth endpoints, scriptable tools) and the contract suites
/// `mcpClientContract` (transport implementations) and `mcpSecretsContract`
/// (`McpSecrets` implementations).
///
/// Depends on `package:test`; import it only from tests (or test servers).
library;

import 'testing/fake_mcp_server.dart';

export 'fakes.dart';
export 'testing/fake_mcp_server.dart';
export 'testing/mcp_client_contract.dart';
export 'testing/mcp_secrets_contract.dart';
