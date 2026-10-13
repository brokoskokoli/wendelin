/// MCP client for Wendelin: Streamable HTTP and Legacy-SSE transport,
/// JSON-RPC lifecycle, OAuth 2.1 (logic only, the browser step is an
/// interface), and the mapping of MCP servers onto the tool system
/// ([McpIntegration], [McpTool]).
///
/// Fakes are in `package:wendelin_mcp/fakes.dart`, the `FakeMcpServer` and
/// the contract suite in `package:wendelin_mcp/testing.dart`.
library;

import 'src/tools/mcp_integration.dart';

export 'src/client.dart';
export 'src/config.dart';
export 'src/errors.dart';
export 'src/net_policy.dart';
export 'src/oauth/oauth_flow.dart';
export 'src/oauth/pkce.dart';
export 'src/ports.dart';
export 'src/protocol.dart';
export 'src/tools/mcp_integration.dart';
export 'src/tools/naming.dart';
export 'src/tools/result.dart';
export 'src/tools/risk.dart';
export 'src/tools/schema.dart';
export 'src/transport/http_call.dart' show McpLog, McpTimeouts;
export 'src/transport/legacy_sse.dart';
export 'src/transport/streamable_http.dart';
export 'src/transport/transport.dart';
