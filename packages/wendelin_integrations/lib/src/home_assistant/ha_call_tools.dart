import 'package:wendelin_core/wendelin_core.dart';

import '../common/base_tool.dart';
import '../common/port_exception.dart';
import '../common/tool_args.dart';
import 'ha_context.dart';
import 'ha_model.dart';
import 'ha_policy.dart';
import 'ha_prompt.dart';
import 'ha_undo.dart';

const _hvacModes = {
  'off', 'heat', 'cool', 'heat_cool', 'auto', 'dry', 'fan_only', //
};

/// German phrase for a service in confirmation texts.
String haServiceText(String service, Map<String, Object?> data) =>
    switch (service) {
      'turn_on' => 'einschalten',
      'turn_off' => 'ausschalten',
      'toggle' => 'umschalten',
      'lock' => 'abschließen',
      'unlock' => 'aufschließen',
      'open' || 'open_cover' => 'öffnen',
      'close_cover' => 'schließen',
      'stop_cover' => 'anhalten',
      'alarm_arm_home' => 'scharf schalten (zu Hause)',
      'alarm_arm_away' => 'scharf schalten (abwesend)',
      'alarm_arm_night' => 'scharf schalten (Nacht)',
      'alarm_disarm' => 'deaktivieren',
      'media_play' => 'abspielen',
      'media_pause' => 'pausieren',
      'media_play_pause' => 'abspielen/pausieren',
      'media_stop' => 'stoppen',
      'media_next_track' => 'nächster Titel',
      'media_previous_track' => 'vorheriger Titel',
      'volume_up' => 'lauter',
      'volume_down' => 'leiser',
      'set_temperature' => 'Temperatur ${data['temperature'] ?? ''}'.trim(),
      'set_cover_position' => 'auf ${data['position'] ?? ''} %'.trim(),
      _ => service,
    };

/// Flat tool argument → key of the Home Assistant service data.
const _dataKeys = {
  'brightness_pct': 'brightness_pct',
  'position_pct': 'position',
  'color_temp_kelvin': 'color_temp_kelvin',
  'rgb_color': 'rgb_color',
  'volume_pct': 'volume_level',
  'muted': 'is_volume_muted',
  'temperature': 'temperature',
  'hvac_mode': 'hvac_mode',
  'preset_mode': 'preset_mode',
};

/// Reads the value arguments of a call, checks that [allowed] (the data keys
/// of the service) covers them and returns the service data. Throws
/// [InvalidArgumentsException].
Map<String, Object?> checkHaData(ToolArgs args, Set<String> allowed) {
  final out = <String, Object?>{};
  for (final MapEntry(:key, :value) in _dataKeys.entries) {
    if (!args.has(key)) continue;
    if (!allowed.contains(value)) {
      throw InvalidArgumentsException(
        '„$key“ passt nicht zu diesem Dienst'
        '${allowed.isEmpty ? ' (keine Werte erlaubt)' : ''}',
      );
    }
    out[value] = switch (key) {
      'brightness_pct' => args.requireInt(key, min: 0, max: 100),
      'position_pct' => args.requireInt(key, min: 0, max: 100),
      'color_temp_kelvin' => args.requireInt(key, min: 1000, max: 10000),
      'rgb_color' => _rgb(args.raw[key]),
      'volume_pct' => args.requireInt(key, min: 0, max: 100) / 100,
      'muted' =>
        args.optBool(key) ??
            (throw const InvalidArgumentsException('„muted“ fehlt')),
      'temperature' => _temperature(args.raw[key]),
      'hvac_mode' => _oneOf(key, args.raw[key], _hvacModes),
      _ => ellipsize(args.requireString(key), 40),
    };
  }
  return out;
}

num _temperature(Object? v) {
  final n = v is String ? num.tryParse(v.trim().replaceAll(',', '.')) : v;
  if (n is! num || n < -50 || n > 100) {
    throw const InvalidArgumentsException(
      '„temperature“ muss eine Zahl zwischen -50 und 100 sein',
    );
  }
  return n;
}

List<int> _rgb(Object? v) {
  final l = ToolArgs({'rgb_color': v})
      .optIntList('rgb_color', min: 0, max: 255);
  if (l == null || l.length != 3) {
    throw const InvalidArgumentsException('„rgb_color“ braucht drei Werte');
  }
  return l;
}

String _oneOf(String key, Object? v, Set<String> allowed) {
  if (v is! String || !allowed.contains(v)) {
    throw InvalidArgumentsException(
      '„$key“ muss eines von ${allowed.join(', ')} sein',
    );
  }
  return v;
}

/// Shared logic of `ha__call` and `ha__call_secure`. A tool only touches
/// the domains of its own table, so the risk class is a property of the
/// tool and never of the model's arguments.
abstract base class HaCallTool extends IntegrationTool {
  /// Creates the tool.
  const HaCallTool(this.ctx);

  /// Shared context.
  final HaContext ctx;

  /// Domains and services this tool may call.
  HaServices get table;

  /// The services of [e] this tool may call, `null` if [e] belongs to the
  /// other tool. [confirmed]: the entity needs a confirmation (the user
  /// marked it „immer bestätigen“, or it is a scene with a lock, alarm or
  /// cover among its members).
  Map<String, Set<String>>? servicesFor(HaEntity e, {required bool confirmed});

  /// Service names offered in the tool schema.
  Set<String> get serviceNames => {for (final s in table.values) ...s.keys};

  /// Name of the tool for the other class of domains.
  String get otherTool;

  /// Whether a successful call offers undo.
  bool get withUndo;

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'properties': {
      'entity': {
        'type': 'string',
        'description':
            'Device as the user says it, e.g. "Küche Deckenlicht" (or the '
            'entity id from ha__list_entities).',
      },
      'service': {
        'type': 'string',
        'enum': [...serviceNames],
        'description': 'What to do (valid for the type of the device).',
      },
      'brightness_pct': {
        'type': 'integer',
        'description': 'Light brightness in percent (0-100).',
      },
      'color_temp_kelvin': {
        'type': 'integer',
        'description': 'Light color temperature in Kelvin, e.g. 2700.',
      },
      'rgb_color': {
        'type': 'array',
        'items': {'type': 'integer'},
        'description': 'Light color as [red, green, blue], each 0-255.',
      },
      'position_pct': {
        'type': 'integer',
        'description':
            'Cover (blind, shutter) position in percent: 0 closed, 100 '
            'fully open. Only with service set_cover_position.',
      },
      'volume_pct': {
        'type': 'integer',
        'description': 'Media player volume in percent (0-100).',
      },
      'muted': {
        'type': 'boolean',
        'description': 'Media player: true = mute, false = unmute.',
      },
      'temperature': {
        'type': 'string',
        'description': 'Thermostat target temperature, e.g. "21.5".',
      },
      'hvac_mode': {
        'type': 'string',
        'description': 'Thermostat mode: off, heat, cool, heat_cool, auto.',
      },
      'preset_mode': {
        'type': 'string',
        'description': 'Thermostat preset, e.g. "eco" or "home".',
      },
    },
    'required': ['entity', 'service'],
  };

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext c) async {
    final query = args.requireString('entity');
    final service = args.requireString('service');
    final e = await ctx.resolve(query);
    // A scene is as critical as its members: look at them before choosing
    // the tool (K57).
    Future<HaState> read() => ctx.guard(() => ctx.api.state(e.entityId));
    HaState? prior;
    if (e.domain == 'scene') prior = await read();
    final confirmed =
        e.alwaysConfirm ||
        (prior != null &&
            haSceneHasSecureMember(prior, confirmIds: await ctx.confirmIds()));
    final services = servicesFor(e, confirmed: confirmed);
    if (services == null) {
      return ToolOutcome.error(
        haRiskForDomain(e.domain) == null
            ? '„${e.name}“ (${e.domain}) kann nur gelesen werden (ha__state).'
            : '„${e.name}“ (${e.domain}) wird mit $otherTool gesteuert.',
        summary: 'Falsches Tool',
      );
    }
    final allowed = services[service];
    if (allowed == null) {
      return ToolOutcome.error(
        'Für ${e.domain} ist „$service“ nicht erlaubt. Erlaubt: '
        '${services.keys.join(', ')}.',
        summary: 'Nicht erlaubt',
      );
    }
    final data = checkHaData(args, allowed);
    // Fail-closed: a position call without a position must not reach HA.
    if (service == 'set_cover_position' && data['position'] == null) {
      throw const InvalidArgumentsException('„position_pct“ fehlt (0 bis 100)');
    }
    final state = prior ?? await read();
    if (state.isUnavailable) {
      return ToolOutcome.error(
        '„${e.name}“ ist gerade nicht erreichbar.',
        summary: 'Nicht erreichbar',
      );
    }
    final plan = withUndo ? planHaUndo(state, service, c.clock.now()) : null;
    final ready = await _prepare(plan);
    await ctx.guard(
      () => ctx.api.callService((
        domain: e.domain,
        service: service,
        data: {'entity_id': e.entityId, ...data},
      )),
    );
    return jsonOutcome(
      {
        'ok': true,
        'device': ellipsize(e.name, maxHaText),
        'service': service,
        'state_before': ellipsize(state.state, 30),
      },
      summary: '${ellipsize(e.name, 40)}: ${haServiceText(service, data)}',
      undo: ready == null ? null : _undo(e.name, ready),
      fixed: _fixed(e, service, data),
    );
  }

  /// The fixed confirmation of a call that ran (WP122, WP135 C), built from
  /// the entity and the validated service data Home Assistant accepted;
  /// `null` = the model words the answer. Only sentences whose key the tool
  /// declared in `confirmationKeys` are used.
  ConfirmationSentence? _fixed(
    HaEntity e,
    String service,
    Map<String, Object?> data,
  ) {
    final device = ellipsize(e.name, 40);
    ConfirmationSentence with_(String key, Object? value) =>
        ConfirmationSentence(key, {'device': device, 'value': ?value});
    final onOff = service == 'turn_on' || service == 'turn_off';
    final sentence = switch ((e.domain, service)) {
      // Scenes, scripts and everything with several values → model.
      ('scene' || 'script', _) => null,
      (_, _) when onOff && data.isEmpty => ConfirmationSentence(
        service == 'turn_on' ? 'ha.on' : 'ha.off',
        {'device': device},
      ),
      ('light', 'turn_on') when _only(data, 'brightness_pct') => with_(
        'ha.brightness',
        data['brightness_pct'],
      ),
      ('climate', 'set_temperature') when _only(data, 'temperature') => with_(
        'ha.temperature',
        data['temperature'],
      ),
      ('cover', 'open_cover') when data.isEmpty => with_('ha.cover.open', null),
      ('cover', 'close_cover') when data.isEmpty => with_(
        'ha.cover.close',
        null,
      ),
      ('cover', 'stop_cover') when data.isEmpty => with_('ha.cover.stop', null),
      ('cover', 'set_cover_position') when _only(data, 'position') => with_(
        'ha.cover.position',
        data['position'],
      ),
      _ => null,
    };
    if (sentence == null) return null;
    final keys = switch (this) {
      final FixedConfirmationTool t => t.confirmationKeys,
      _ => const <String>{},
    };
    return keys.contains(sentence.key) ? sentence : null;
  }

  static bool _only(Map<String, Object?> data, String key) =>
      data.length == 1 && data[key] is num;

  /// Runs the pre-steps of [plan] (scene snapshot); `null` when they fail,
  /// the call then runs without undo.
  Future<HaUndoPlan?> _prepare(HaUndoPlan? plan) async {
    if (plan == null) return null;
    try {
      for (final call in plan.before) {
        await ctx.guard(() => ctx.api.callService(call));
      }
    } on PortException {
      return null;
    }
    return plan;
  }

  UndoAction _undo(String name, HaUndoPlan plan) => UndoAction(
    label: '${ellipsize(name, 40)} zurücksetzen',
    run: () async {
      for (final call in plan.restore) {
        await ctx.guard(() => ctx.api.callService(call));
      }
    },
  );

  @override
  String describe(ToolArgs args) =>
      '${args.requireString('entity')}: ${haServiceText(args.requireString('service'), {'temperature': args.optString('temperature'), 'position': args.raw['position_pct']})}';

  @override
  String get fallbackDescription => 'Smart-Home-Gerät steuern';
}

/// `ha__call` (write): light, switch, scene, media player, climate. Runs
/// without a question and offers undo to the previous state.
final class HaCallDeviceTool extends HaCallTool
    implements FixedConfirmationTool, PromptContributor {
  /// Creates the tool.
  const HaCallDeviceTool(super.ctx);

  @override
  String get name => 'ha__call';

  @override
  String get description =>
      'Control a smart-home device the user approved: lights, switches, '
      'scenes, media players and thermostats (not locks, alarms or doors: '
      'use ha__call_secure). Runs at once; can be undone.';

  @override
  RiskLevel get risk => RiskLevel.write;

  @override
  Set<String> get confirmationKeys => const {
    'ha.on',
    'ha.off',
    'ha.brightness',
    'ha.temperature',
  };

  @override
  Future<String?> promptSection(String requestText) async {
    try {
      return await haPromptSection(ctx, requestText);
    } on Object {
      return null;
    }
  }

  @override
  HaServices get table => haOpenServices;

  @override
  Map<String, Set<String>>? servicesFor(
    HaEntity e, {
    required bool confirmed,
  }) => confirmed ? null : haOpenServices[e.domain];

  @override
  String get otherTool => 'ha__call_secure';

  @override
  bool get withUndo => true;
}

/// `ha__call_secure` (external): locks, alarm panels and covers (garage,
/// gate, door). Always needs the user's confirmation; no undo.
final class HaCallSecureTool extends HaCallTool
    implements ConfirmationPreparer, FixedConfirmationTool {
  /// Creates the tool.
  const HaCallSecureTool(super.ctx);

  @override
  String get name => 'ha__call_secure';

  @override
  String get description =>
      'Control a lock, alarm panel, garage door, gate or other cover, a '
      'scene that switches one of them, or a device the user marked as '
      '"always confirm". The user is always asked first.';

  @override
  RiskLevel get risk => RiskLevel.external;

  /// The sentences after a confirmed cover call (blinds, shutters, doors).
  @override
  Set<String> get confirmationKeys => const {
    'ha.cover.open',
    'ha.cover.close',
    'ha.cover.stop',
    'ha.cover.position',
  };

  @override
  HaServices get table => haSecureServices;

  @override
  Set<String> get serviceNames => {
    ...super.serviceNames,
    // Switches and scenes the user or the scene's members make critical.
    ...?haOpenServices['switch']?.keys,
    ...?haOpenServices['scene']?.keys,
  };

  @override
  Map<String, Set<String>>? servicesFor(
    HaEntity e, {
    required bool confirmed,
  }) =>
      haSecureServices[e.domain] ??
      (confirmed &&
              (e.alwaysConfirm
                  ? haOpenServices.containsKey(e.domain)
                  : e.domain == 'scene')
          ? haOpenServices[e.domain]
          : null);

  @override
  String get otherTool => 'ha__call';

  @override
  bool get withUndo => false;

  @override
  Future<String> prepareConfirmation(
    Map<String, Object?> args,
    ToolContext c,
  ) async {
    final a = ToolArgs(args);
    final e = await ctx.resolve(a.requireString('entity'));
    final room = e.area == null ? '' : ' (${e.area})';
    return '${e.name}$room: ${haServiceText(a.requireString('service'), {'position': a.raw['position_pct']})}';
  }
}
