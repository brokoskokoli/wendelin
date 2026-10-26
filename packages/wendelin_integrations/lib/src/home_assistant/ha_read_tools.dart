import 'dart:convert';

import 'package:wendelin_core/wendelin_core.dart';

import '../common/base_tool.dart';
import '../common/matching.dart';
import '../common/tool_args.dart';
import 'ha_context.dart';
import 'ha_model.dart';
import 'ha_policy.dart';

const _entityProp = {
  'type': 'string',
  'description':
      'Device as the user says it, e.g. "Küche Deckenlicht" (or the '
      'entity id from ha__list_entities).',
};

/// Attributes of a state that are passed to the model (everything else
/// stays in Home Assistant).
const _shownAttributes = [
  'unit_of_measurement',
  'device_class',
  'current_temperature',
  'temperature',
  'target_temp_low',
  'target_temp_high',
  'hvac_action',
  'hvac_modes',
  'preset_mode',
  'volume_level',
  'is_volume_muted',
  'media_title',
  'media_artist',
  'source',
  'current_position',
  'battery_level',
  'color_temp_kelvin',
  'rgb_color',
];

Object? _safeValue(Object? v) => switch (v) {
  final String s => ellipsize(s, maxHaText),
  final List<Object?> l => [for (final e in l.take(10)) _safeValue(e)],
  final num _ || final bool _ || null => v,
  _ => null,
};

/// The state as shown to the model: texts shortened, brightness as percent.
Map<String, Object?> haStateJson(HaEntity e, HaState s, {bool full = true}) {
  final a = s.attributes;
  return {
    'id': e.entityId,
    'name': ellipsize(e.name, maxHaText),
    if (e.area != null) 'area': ellipsize(e.area!, maxHaText),
    'state': ellipsize(s.state, maxHaText),
    if (full) ...{
      if (a['brightness'] is num)
        'brightness_pct': ((a['brightness']! as num) / 2.55).round(),
      for (final k in _shownAttributes)
        if (a[k] != null) k: _safeValue(a[k]),
    },
  };
}

/// `ha__list_entities` (read): the approved devices with name and room.
final class HaListEntitiesTool extends IntegrationTool
    implements NoNetworkTarget, TrustedContentSource {
  /// Creates the tool.
  const HaListEntitiesTool(this.ctx);

  /// Shared context.
  final HaContext ctx;

  @override
  String get name => 'ha__list_entities';

  @override
  String get description =>
      'List the smart-home devices (Home Assistant) the user approved, with '
      'name, room (area) and type (domain: light, switch, scene, '
      'media_player, climate, lock, cover, sensor, …). Optional filters.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'required': <String>[],
    'properties': {
      'area': {
        'type': 'string',
        'description': 'Only this room, e.g. "Küche".',
      },
      'domain': {
        'type': 'string',
        'description': 'Only this type, e.g. "light".',
      },
    },
  };

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext c) async {
    final area = args.optString('area');
    final domain = args.optString('domain')?.toLowerCase();
    final all = await ctx.approved();
    final shown = [
      for (final e in all)
        if ((area == null || area.isEmpty || _inArea(e, area)) &&
            (domain == null || domain.isEmpty || e.domain == domain))
          e,
    ];
    return ToolOutcome.text(
      '$haDataNotice\n${jsonEncode(_entitiesJson(shown, all.length))}',
      summary: '${shown.length} Geräte',
    );
  }

  static bool _inArea(HaEntity e, String area) =>
      e.area != null && matchScore(area, e.area!) > 0;

  @override
  String describe(ToolArgs args) => 'Smart-Home-Geräte anzeigen';

  @override
  String get fallbackDescription => 'Smart-Home-Geräte anzeigen';
}

/// `ha__state` (read): state of one device, or of several.
final class HaStateTool extends IntegrationTool
    implements NoNetworkTarget, TrustedContentSource {
  /// Creates the tool.
  const HaStateTool(this.ctx);

  /// Shared context.
  final HaContext ctx;

  /// Most devices listed without `entity`.
  static const maxStates = 40;

  @override
  String get name => 'ha__state';

  @override
  String get description =>
      'Read the current state of a smart-home device (on/off, brightness, '
      'temperature, lock, …). Without "entity" the states of the approved '
      'devices, optionally filtered by room or type.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'required': <String>[],
    'properties': {
      'entity': _entityProp,
      'area': {'type': 'string', 'description': 'Only this room.'},
      'domain': {
        'type': 'string',
        'description': 'Only this type, e.g. "light".',
      },
    },
  };

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext c) async {
    final query = args.optString('entity');
    if (query != null && query.isNotEmpty) {
      final e = await ctx.resolve(query);
      final s = await ctx.guard(() => ctx.api.state(e.entityId));
      return ToolOutcome.text(
        '$haDataNotice\n${jsonEncode(haStateJson(e, s))}',
        summary: '${e.name}: ${ellipsize(s.state, 30)}',
      );
    }
    final area = args.optString('area');
    final domain = args.optString('domain')?.toLowerCase();
    final all = await ctx.approved();
    final picked = [
      for (final e in all)
        if ((area == null ||
                area.isEmpty ||
                (e.area != null && matchScore(area, e.area!) > 0)) &&
            (domain == null || domain.isEmpty || e.domain == domain))
          e,
    ];
    final states = {
      for (final s in await ctx.guard(ctx.api.states)) s.entityId: s,
    };
    final rows = [
      for (final e in picked.take(maxStates))
        if (states[e.entityId] case final s?) haStateJson(e, s, full: false),
    ];
    return ToolOutcome.text(
      '$haDataNotice\n${jsonEncode({'devices': rows, if (picked.length > maxStates) 'more': picked.length - maxStates})}',
      summary: '${rows.length} Geräte',
    );
  }

  @override
  String describe(ToolArgs args) {
    final e = args.optString('entity');
    return e == null || e.isEmpty
        ? 'Gerätezustände lesen'
        : 'Zustand von $e lesen';
  }

  @override
  String get fallbackDescription => 'Gerätezustand lesen';
}

Map<String, Object?> _entitiesJson(List<HaEntity> shown, int total) => {
  'devices': [
    for (final e in shown)
      {
        'id': e.entityId,
        'name': ellipsize(e.name, maxHaText),
        if (e.area != null) 'area': ellipsize(e.area!, maxHaText),
        'domain': e.domain,
        if (haRiskForDomain(e.domain) == null) 'read_only': true,
      },
  ],
  if (shown.length != total) 'total': total,
};
