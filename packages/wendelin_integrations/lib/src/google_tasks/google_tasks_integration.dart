import 'package:wendelin_core/wendelin_core.dart';

import '../common/port_exception.dart';
import 'google_oauth.dart';
import 'google_tasks_api.dart';
import 'google_tasks_session.dart';
import 'google_tasks_tools.dart';

/// Google Tasks (`gtasks__…` tools, same form as `tasks__…`) over the Tasks
/// API with OAuth (the user's own Cloud project, loopback redirect).
///
/// [onError] / [onRecovered] connect the error state to the app (usually
/// `ToolRegistry.reportError` / `clearError`); see [GoogleTasksSession].
final class GoogleTasksIntegration implements Integration {
  /// Creates the integration.
  GoogleTasksIntegration(
    GoogleTasksApi api,
    GoogleOAuthApi oauth,
    this.secrets, {
    void Function(String message)? onError,
    void Function()? onRecovered,
    Clock clock = const SystemClock(),
  }) : session = GoogleTasksSession(
         api,
         oauth,
         secrets,
         onError: onError,
         onRecovered: onRecovered,
         clock: clock,
       );

  /// Id of the setup step „Google login“.
  static const loginStep = 'google_tasks_login';

  /// Where client and refresh token live.
  final GoogleTasksSecrets secrets;

  /// Token handling and error state shared by the tools.
  final GoogleTasksSession session;

  @override
  String get id => 'gtasks';

  @override
  String get displayName => 'Google Tasks';

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
      id: loginStep,
      kind: SetupStepKind.login,
      label: 'Google-Anmeldung fehlt',
    ),
  ];

  @override
  Future<SetupState> setupState() async {
    final client = await secrets.client();
    final token = await secrets.refreshToken();
    return SetupState(
      missingSteps: [
        if (client == null || token == null || token.isEmpty) loginStep,
      ],
    );
  }

  @override
  late final List<Tool> tools = List.unmodifiable(<Tool>[
    GoogleTasksAddTool(session),
    GoogleTasksListTool(session),
    GoogleTasksCompleteTool(session),
  ]);

  /// Tests the login (reads the lists), e.g. after the setup or from
  /// „Erneut versuchen“. Returns `null` on success (error state cleared via
  /// `onRecovered`), else a German message.
  Future<String?> reconnect() async {
    try {
      session.reset();
      await session.lists();
      return null;
    } on PortException catch (e) {
      return e.message;
    }
  }
}
