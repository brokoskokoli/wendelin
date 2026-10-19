import 'package:wendelin_core/wendelin_core.dart';

import '../common/port_exception.dart';
import 'todoist_api.dart';
import 'todoist_session.dart';
import 'todoist_tools.dart';

/// Todoist tasks (`todoist__…` tools, same form as `tasks__…`) over the
/// Todoist API v1 with the user's personal API token.
///
/// [onError] / [onRecovered] connect the error state to the app (usually
/// `ToolRegistry.reportError` / `clearError`); see [TodoistSession].
final class TodoistIntegration implements Integration {
  /// Creates the integration.
  TodoistIntegration(
    TodoistApi api,
    this.secrets, {
    void Function(String message)? onError,
    void Function()? onRecovered,
  }) : session = TodoistSession(
         api,
         secrets,
         onError: onError,
         onRecovered: onRecovered,
       );

  /// Id of the setup step „Todoist token“.
  static const tokenStep = 'todoist_token';

  /// Where the token lives.
  final TodoistSecrets secrets;

  /// Token handling and error state shared by the tools.
  final TodoistSession session;

  @override
  String get id => 'todoist';

  @override
  String get displayName => 'Todoist';

  @override
  String get iconId => 'task';

  @override
  Set<AppPlatform> get platforms => const {
    AppPlatform.android,
    AppPlatform.ios,
  };

  @override
  bool get sensitive => false;

  @override
  Future<Availability> checkAvailability() async => Availability.yes;

  @override
  List<SetupStep> get setup => const [
    SetupStep(
      id: tokenStep,
      kind: SetupStepKind.login,
      label: 'API-Token fehlt',
    ),
  ];

  @override
  Future<SetupState> setupState() async {
    final token = await secrets.token();
    return SetupState(
      missingSteps: [if (token == null || token.isEmpty) tokenStep],
    );
  }

  @override
  late final List<Tool> tools = List.unmodifiable(<Tool>[
    TodoistAddTool(session),
    TodoistListTool(session),
    TodoistCompleteTool(session),
  ]);

  /// Tests the token (reads the projects), e.g. after the setup or from
  /// „Erneut versuchen“. Returns `null` on success (error state cleared via
  /// `onRecovered`), else a German message.
  Future<String?> reconnect() async {
    try {
      await session.projects();
      return null;
    } on PortException catch (e) {
      return e.message;
    }
  }
}
