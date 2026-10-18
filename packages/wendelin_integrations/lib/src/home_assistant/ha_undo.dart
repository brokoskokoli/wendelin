import 'ha_model.dart';

/// What to do to undo a service call, planned from the state before it.
/// [before] runs before the call (scene snapshot), [restore] on undo.
typedef HaUndoPlan = ({List<HaCall> before, List<HaCall> restore});

Map<String, Object?> _ent(HaState s, [Map<String, Object?> data = const {}]) =>
    {'entity_id': s.entityId, ...data};

HaCall _call(
  HaState s,
  String service, [
  Map<String, Object?> data = const {},
]) => (domain: s.domain, service: service, data: _ent(s, data));

/// Plans the undo of [service] on [prior] (the state before the call), or
/// `null` if nothing sensible can be restored (unavailable entity, a call
/// that changes nothing, next/previous track). [now] makes the id of the
/// scene snapshot unique.
HaUndoPlan? planHaUndo(HaState prior, String service, DateTime now) {
  if (prior.isUnavailable) return null;
  final restore = switch (prior.domain) {
    'light' => _light(prior),
    'switch' => [_call(prior, prior.state == 'on' ? 'turn_on' : 'turn_off')],
    'media_player' => _media(prior, service),
    'climate' => _climate(prior, service),
    _ => null,
  };
  if (prior.domain == 'scene') return _scene(prior, now);
  if (restore == null || restore.isEmpty) return null;
  return (before: const [], restore: restore);
}

List<HaCall> _light(HaState s) {
  if (s.state != 'on') return [_call(s, 'turn_off')];
  final a = s.attributes;
  return [
    _call(s, 'turn_on', {
      if (a['brightness'] is num) 'brightness': a['brightness'],
      if (a['color_mode'] == 'color_temp' && a['color_temp_kelvin'] is num)
        'color_temp_kelvin': a['color_temp_kelvin']
      else if (a['rgb_color'] is List<Object?>)
        'rgb_color': a['rgb_color'],
    }),
  ];
}

List<HaCall>? _media(HaState s, String service) {
  final volume = s.attributes['volume_level'];
  final muted = s.attributes['is_volume_muted'];
  return switch (service) {
    'turn_on' ||
    'turn_off' => [_call(s, s.state == 'off' ? 'turn_off' : 'turn_on')],
    'media_play' ||
    'media_pause' ||
    'media_play_pause' ||
    'media_stop' => switch (s.state) {
      'playing' => [_call(s, 'media_play')],
      'paused' => [_call(s, 'media_pause')],
      _ => null,
    },
    'volume_up' || 'volume_down' || 'volume_set' =>
      volume is num
          ? [
              _call(s, 'volume_set', {'volume_level': volume}),
            ]
          : null,
    'volume_mute' =>
      muted is bool
          ? [
              _call(s, 'volume_mute', {'is_volume_muted': muted}),
            ]
          : null,
    _ => null,
  };
}

List<HaCall>? _climate(HaState s, String service) {
  final a = s.attributes;
  return switch (service) {
    'set_temperature' => [
      if (a['temperature'] is num)
        _call(s, 'set_temperature', {'temperature': a['temperature']})
      else if (a['target_temp_low'] is num && a['target_temp_high'] is num)
        _call(s, 'set_temperature', {
          'target_temp_low': a['target_temp_low'],
          'target_temp_high': a['target_temp_high'],
        }),
    ],
    'set_hvac_mode' || 'turn_on' || 'turn_off' => [
      _call(s, 'set_hvac_mode', {'hvac_mode': s.state}),
    ],
    'set_preset_mode' => switch (a['preset_mode']) {
      final String p => [
        _call(s, 'set_preset_mode', {'preset_mode': p}),
      ],
      _ => null,
    },
    _ => null,
  };
}

/// A scene is restored by Home Assistant's own snapshot: `scene.create`
/// stores the current state of the scene's entities under a temporary
/// scene, undo activates it and deletes it again.
HaUndoPlan? _scene(HaState scene, DateTime now) {
  final members = scene.attributes['entity_id'];
  if (members is! List<Object?> || members.isEmpty) return null;
  final id = 'wendelin_undo_${now.millisecondsSinceEpoch}';
  return (
    before: [
      (
        domain: 'scene',
        service: 'create',
        data: {
          'scene_id': id,
          'snapshot_entities': [for (final m in members) m.toString()],
        },
      ),
    ],
    restore: [
      (domain: 'scene', service: 'turn_on', data: {'entity_id': 'scene.$id'}),
      (domain: 'scene', service: 'delete', data: {'entity_id': 'scene.$id'}),
    ],
  );
}
