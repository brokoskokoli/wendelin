/// Shared types of all integrations: tool base, argument parsing, data envelope, port exceptions, time helpers and `net_scope` (network target classification).
///
/// Entry point of one integration; `wendelin_integrations.dart` re-exports it.
library;

export 'src/common/base_tool.dart' show IntegrationTool, ellipsize;
export 'src/common/data_envelope.dart';
export 'src/common/net_scope.dart';
export 'src/common/port_exception.dart';
export 'src/common/time.dart' show LocalDate, timeZoneLocation;
export 'src/common/tool_args.dart' show InvalidArgumentsException, ToolArgs;
