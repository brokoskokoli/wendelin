import 'package:wendelin_core/wendelin_core.dart';

import '../common/port_exception.dart';
import 'ha_call_tools.dart';
import 'ha_context.dart';
import 'ha_policy.dart';
import 'ha_ports.dart';
import 'ha_read_tools.dart';

/// Home Assistant (`ha__…` tools): the user's approved devices over the REST
/// API of their own instance (home network or Tailscale).
///
/// [onError] / [onRecovered] connect the error state to the app (usually
/// `ToolRegistry.reportError` / `clearError`).
final class HaIntegration implements Integration {
  /// Creates the integration.
  HaIntegration(
    HaApi api,
    this.secrets,
    this.store, {
    void Function(String message)? onError,
    void Function()? onRecovered,
  }) : context = HaContext(
         api,
         store,
         onError: onError,
         onRecovered: onRecovered,
       );

  /// Id of the setup step „address and token“.
  static const connectStep = 'ha_connect';

  /// Id of the setup step „approve devices“.
  static const entitiesStep = 'ha_entities';

  /// Address and token.
  final HaSecrets secrets;

  /// The approved devices.
  final HaEntityStore store;

  /// API, approved devices and error state shared by the tools.
  final HaContext context;

  @override
  String get id => 'ha';

  @override
  String get displayName => 'Home Assistant (direkt)';

  @override
  String get iconId => 'home';

  @override
  Set<AppPlatform> get platforms => const {
    AppPlatform.android,
    AppPlatform.ios,
  };

  /// Smart-home data is house data: lock and alarm states, who is home,
  /// when rooms are empty. Its tools only go to providers that meet the
  /// configured privacy minimum.
  @override
  bool get sensitive => true;

  @override
  Future<Availability> checkAvailability() async => Availability.yes;

  @override
  List<SetupStep> get setup => const [
    SetupStep(
      id: connectStep,
      kind: SetupStepKind.login,
      label: 'Verbindung fehlt',
    ),
    SetupStep(
      id: entitiesStep,
      kind: SetupStepKind.config,
      label: 'Keine Geräte freigegeben',
    ),
  ];

  @override
  Future<SetupState> setupState() async => SetupState(
    missingSteps: [
      if (await secrets.endpoint() == null) connectStep,
      if ((await store.load()).isEmpty) entitiesStep,
    ],
  );

  @override
  late final List<Tool> tools = List.unmodifiable(<Tool>[
    HaListEntitiesTool(context),
    HaStateTool(context),
    HaCallDeviceTool(context),
    HaCallSecureTool(context),
  ]);

  /// Tests the connection, e.g. after the setup or from „Erneut versuchen“.
  /// Returns `null` on success, else a German message.
  Future<String?> reconnect() async {
    try {
      await context.guard(context.api.check);
      return null;
    } on PortException catch (e) {
      return e.message;
    }
  }

  /// Hook for the speaker recognition (WP92): whether the call of
  /// [toolName] with [args] may run on a locked device. Only `ha__call` on
  /// light, scene and media player ([haLockSafeDomains]); reading (it would
  /// read house details aloud) and locks, alarms, covers and climate are
  /// not. The lock policy itself is not part of WP91; this only answers the
  /// question. Unknown or unresolvable entities are not allowed.
  Future<bool> allowedWhileLocked(
    String toolName,
    Map<String, Object?> args,
  ) async {
    if (toolName != 'ha__call') return false;
    final query = args['entity'];
    if (query is! String || query.trim().isEmpty) return false;
    try {
      final e = await context.resolve(query);
      if (e.alwaysConfirm || !haLockSafeDomains.contains(e.domain)) {
        return false;
      }
      if (e.domain != 'scene') return true;
      // A scene with a lock, alarm or cover is as critical as the member.
      final scene = await context.api.state(e.entityId);
      return haSceneHasMembers(scene) &&
          !haSceneHasSecureMember(
            scene,
            confirmIds: await context.confirmIds(),
          );
    } on PortException {
      return false;
    }
  }
}
