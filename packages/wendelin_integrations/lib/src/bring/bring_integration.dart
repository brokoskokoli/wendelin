import 'package:wendelin_core/wendelin_core.dart';

import '../common/port_exception.dart';
import 'bring_api.dart';
import 'bring_session.dart';
import 'bring_tools.dart';

/// Fallback when the API fails (implemented by the app, WP28): share the
/// item text with the Bring! app.
abstract final class BringAppFallback {
  /// Android package of the Bring! app (share target, app detection).
  static const androidPackage = 'ch.publisheria.bring';

  /// Informative note for the settings page; the integration works without
  /// the app.
  static const note =
      'Die Bring!-App ist nicht nötig. Ist sie installiert, kann Wendelin '
      'Artikel per „Teilen“ an sie übergeben, wenn die Bring!-Schnittstelle '
      'gerade nicht funktioniert.';

  /// Plain text for the share intent: one item per line, spec in
  /// parentheses.
  static String shareText(Iterable<BringItem> items) =>
      [for (final i in items) i.spec.isEmpty ? i.name : '${i.name} (${i.spec})']
          .join('\n');
}

/// Bring! shopping lists (`bring__…` tools) over the unofficial API.
///
/// [onError] / [onRecovered] connect the error state to the app (usually
/// `ToolRegistry.reportError` / `clearError`); see [BringSession].
final class BringIntegration implements Integration {
  /// Creates the integration.
  BringIntegration(
    BringApi api,
    this.secrets, {
    void Function(String message)? onError,
    void Function()? onRecovered,
  }) : session = BringSession(
         api,
         secrets,
         onError: onError,
         onRecovered: onRecovered,
       );

  /// Id of the setup step „Bring! login“.
  static const loginStep = 'bring_login';

  /// Where credentials and tokens live.
  final BringSecrets secrets;

  /// Login handling and error state shared by the tools.
  final BringSession session;

  @override
  String get id => 'bring';

  @override
  String get displayName => 'Bring!';

  @override
  String get iconId => 'shopping_cart';

  @override
  Set<AppPlatform> get platforms => const {
    AppPlatform.android,
    AppPlatform.ios,
  };

  @override
  bool get sensitive => false;

  /// Always available: the API is enough, the app is only a fallback
  /// ([BringAppFallback.note]).
  @override
  Future<Availability> checkAvailability() async => Availability.yes;

  @override
  List<SetupStep> get setup => const [
    SetupStep(
      id: loginStep,
      kind: SetupStepKind.login,
      label: 'Bei Bring! anmelden',
    ),
  ];

  @override
  Future<SetupState> setupState() async => SetupState(
    missingSteps: [if (await secrets.credentials() == null) loginStep],
  );

  @override
  late final List<Tool> tools = List.unmodifiable(<Tool>[
    BringListListsTool(session),
    BringGetItemsTool(session),
    BringAddItemsTool(session),
    BringRemoveItemTool(session),
    BringCompleteItemTool(session),
  ]);

  /// Tests the connection (login if needed, read the lists), e.g. after
  /// the setup or from „Erneut versuchen“. Returns `null` on success
  /// (error state cleared via `onRecovered`), else a German message.
  Future<String?> reconnect() async {
    try {
      await session.lists();
      return null;
    } on PortException catch (e) {
      return e.message;
    }
  }

  /// Forgets the cached session (call after the login changed).
  Future<void> signOut() => session.forget();
}
