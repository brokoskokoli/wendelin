/// User-defined integrations (MCP servers, HTTP tools): the source
/// interface, the removal description and [UserIntegrationSync], which keeps
/// a registry in step with the sources (ADR 0012).
///
/// Entry point of one area; `wendelin_integrations.dart` re-exports it.
library;

export 'src/user/user_integration.dart';
export 'src/user/user_integration_sync.dart';
