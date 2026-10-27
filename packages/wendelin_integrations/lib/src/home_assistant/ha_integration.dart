import 'package:wendelin_core/wendelin_core.dart';

import '../common/port_exception.dart';
import 'ha_call_tools.dart';
import 'ha_context.dart';
import 'ha_fast_path.dart';
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
    void Function(String message, PortErrorKind kind)? onError,
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

  /// The fast path without a model (WP135 D); the agent runs it before the
  /// first model call when the user has not switched it off.
  late final FastPath fastPath = HaFastPath(context);

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
  /// Returns `null` on success, else the failure (the app words it).
  Future<ReconnectFailure?> reconnect() async {
    try {
      await context.guard(context.api.check);
      return null;
    } on PortException catch (e) {
      return ReconnectFailure.of('ha', e);
    }
  }

  /// Whether at least one approved device may be controlled in [access]
  /// (WP154 L2): the locked path then lets the model run with `ha__call`. The
  /// stored data decide (no live state): fail-closed for covers and scenes
  /// without a chosen level. Unreadable data mean no.
  Future<bool> anyAllowedWhileLocked(AccessContext access) async {
    try {
      final critical = await context.confirmIds();
      final kinds = await context.kindLevels();
      for (final e in await context.approved()) {
        if (haRiskForDomain(e.domain) == null) continue;
        if (haDecide(
              e,
              kinds: kinds,
              criticalIds: critical,
              locked: access.locked,
              speakerRecognized: access.speakerRecognized,
            ) ==
            LevelAccess.allowed) {
          return true;
        }
      }
    } on Object {
      return false;
    }
    return false;
  }

  /// Hook for the lock and speaker policy (WP92, WP154): whether the call
  /// of [toolName] with [args] may run on a locked device **for a
  /// recognized voice**, according to the policy table ([haDecide], level
  /// B or A). Only `ha__call`; reading (it would read house details aloud)
  /// never. Unknown or unresolvable entities are not allowed. Nothing calls
  /// this yet (the scope computation asks it with the access of the request).
  Future<bool> allowedWhileLocked(
    String toolName,
    Map<String, Object?> args, {
    AccessContext access = const AccessContext(
      locked: true,
      speakerRecognized: true,
    ),
  }) async {
    if (toolName != 'ha__call') return false;
    final query = args['entity'];
    if (query is! String || query.trim().isEmpty) return false;
    try {
      final e = await context.resolve(query);
      final state = e.domain == 'scene' || e.domain == 'cover'
          ? await context.api.state(e.entityId)
          : null;
      return haDecide(
            e,
            kinds: await context.kindLevels(),
            state: state,
            criticalIds: e.domain == 'scene'
                ? await context.confirmIds()
                : const {},
            locked: true,
            speakerRecognized: access.speakerRecognized,
          ) ==
          LevelAccess.allowed;
    } on PortException {
      return false;
    }
  }
}
