/// Wendelin core contracts: provider-neutral message format, provider,
/// tool, integration and agent interfaces, events, errors and utilities.
///
/// Test fakes and contract suites live in `package:wendelin_core/testing.dart`.
library;

export 'src/agent/agent_event.dart';
export 'src/agent/agent_run.dart';
export 'src/agent/user_input.dart';
export 'src/messages/chat_event.dart';
export 'src/messages/chat_request.dart';
export 'src/messages/content_block.dart';
export 'src/messages/message.dart';
export 'src/messages/role.dart';
export 'src/messages/stop_reason.dart';
export 'src/messages/tool_choice.dart';
export 'src/messages/tool_spec.dart';
export 'src/messages/usage.dart';
export 'src/provider/auth_method.dart';
export 'src/provider/cancel_token.dart';
export 'src/provider/llm_provider.dart';
export 'src/provider/model_info.dart';
export 'src/provider/privacy_level.dart';
export 'src/provider/provider_exception.dart';
export 'src/provider/provider_profile.dart';
export 'src/provider/provider_type.dart';
export 'src/tools/integration.dart';
export 'src/tools/tool.dart';
export 'src/tools/tool_context.dart';
export 'src/tools/tool_outcome.dart';
export 'src/tools/tool_runtime.dart';
export 'src/util/clock.dart';
export 'src/util/id_generator.dart';
