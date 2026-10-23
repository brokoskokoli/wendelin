import '../src/common/port_exception.dart';
import '../src/home_assistant/ha_model.dart';
import '../src/home_assistant/ha_ports.dart';
import '../src/home_assistant/ha_registry.dart';
import 'fake_failures.dart';

/// In-memory Home Assistant for tests and the demo mode: a small house
/// with the typical domains and the service semantics of Home Assistant
/// (light brightness, scene members, scene snapshots via `scene.create`).
///
/// [calls] records every service call. A test server
/// (`test/home_assistant/ha_server.dart`) serves this state over real
/// REST/WebSocket for `HttpHaApi`.
final class FakeHaApi with FakeFailures implements HaApi {
  /// Creates the house (see [reset]).
  FakeHaApi() {
    reset();
  }

  /// States by entity id.
  final Map<String, HaState> _states = {};

  /// Room per entity id.
  final Map<String, String> areas = {};

  /// Entities activated by a scene (scene id → states set on activation).
  final Map<String, Map<String, HaState>> sceneMembers = {};

  /// Every `callService` in order (after failure injection).
  final List<HaCall> calls = [];

  /// Version returned by [check].
  String version = '2026.10.0';

  /// Whether the registries (rooms) are readable (admin token).
  bool admin = true;

  /// Restores the standard house: `light.kitchen` (on, 200), `light.bedroom`
  /// (off), `light.living` (on, 255), `switch.coffee`, `scene.movie`,
  /// `media_player.tv` (playing, volume 0.3), `climate.living` (heat, 21),
  /// `lock.front`, `cover.garage`, `alarm_control_panel.home`,
  /// `sensor.temp_out` (12.5 °C), `light.secret` (not approved by tests).
  void reset() {
    _states.clear();
    areas
      ..clear()
      ..addAll({
        'light.kitchen': 'Küche',
        'switch.coffee': 'Küche',
        'light.bedroom': 'Schlafzimmer',
        'light.living': 'Wohnzimmer',
        'scene.movie': 'Wohnzimmer',
        'media_player.tv': 'Wohnzimmer',
        'climate.living': 'Wohnzimmer',
        'lock.front': 'Flur',
        'cover.garage': 'Garage',
        'alarm_control_panel.home': 'Flur',
      });
    calls.clear();
    sceneMembers.clear();
    void put(String id, String state, Map<String, Object?> attrs, String name) {
      _states[id] = HaState(
        entityId: id,
        state: state,
        attributes: {'friendly_name': name, ...attrs},
      );
    }

    put('light.kitchen', 'on', {
      'brightness': 200,
      'color_mode': 'brightness',
    }, 'Küche Deckenlicht');
    put('light.bedroom', 'off', {}, 'Schlafzimmer Licht');
    put('light.living', 'on', {'brightness': 255}, 'Wohnzimmer Licht');
    put('light.secret', 'on', {'brightness': 10}, 'Geheimes Licht');
    put('switch.coffee', 'off', {}, 'Kaffeemaschine');
    put('scene.movie', 'scening', {
      'entity_id': ['light.living', 'media_player.tv'],
    }, 'Filmabend');
    put('media_player.tv', 'playing', {
      'volume_level': 0.3,
      'is_volume_muted': false,
      'media_title': 'Tagesschau',
    }, 'Fernseher');
    put('climate.living', 'heat', {
      'temperature': 21,
      'current_temperature': 20.5,
      'preset_mode': 'home',
      'hvac_modes': ['off', 'heat'],
    }, 'Heizung Wohnzimmer');
    put('lock.front', 'locked', {}, 'Haustür');
    put('cover.garage', 'closed', {'device_class': 'garage'}, 'Garagentor');
    put('alarm_control_panel.home', 'disarmed', {}, 'Alarmanlage');
    put('sensor.temp_out', '12.5', {
      'unit_of_measurement': '°C',
      'device_class': 'temperature',
    }, 'Außentemperatur');
    sceneMembers['scene.movie'] = {
      'light.living': const HaState(
        entityId: 'light.living',
        state: 'on',
        attributes: {'brightness': 20},
      ),
      'media_player.tv': const HaState(
        entityId: 'media_player.tv',
        state: 'playing',
        attributes: {'volume_level': 0.1},
      ),
    };
  }

  /// Removes an entity as if the user deleted it in Home Assistant.
  void remove(String id) {
    _states.remove(id);
    areas.remove(id);
  }

  void _setCoverPosition(String id, Object? position) {
    if (position is! int) {
      throw const PortException(
        PortErrorKind.failed,
        'Unerwartete Antwort von Home Assistant (HTTP 400).',
      );
    }
    set(id, position > 0 ? 'open' : 'closed', {'current_position': position});
  }

  /// Sets a state directly (test setup).
  void set(
    String id,
    String state, [
    Map<String, Object?> attributes = const {},
  ]) {
    final old = _states[id];
    _states[id] = HaState(
      entityId: id,
      state: state,
      attributes: {...?old?.attributes, ...attributes},
    );
  }

  /// Current state of [id], `null` if unknown (test assertions).
  HaState? at(String id) => _states[id];

  @override
  Future<String> check() async {
    enter('check');
    return version;
  }

  @override
  Future<List<HaState>> states() async {
    enter('states');
    return _states.values.toList();
  }

  @override
  Future<HaState> state(String entityId) async {
    enter('state');
    return _states[entityId] ??
        (throw const PortException(
          PortErrorKind.notFound,
          'Nicht gefunden in Home Assistant.',
        ));
  }

  @override
  Future<List<HaEntity>> entities() async {
    enter('entities');
    return haEntitiesFrom(_states.values.toList(), admin ? areas : const {});
  }

  @override
  Future<void> callService(HaCall call) async {
    enter('callService');
    calls.add(call);
    final id = call.data['entity_id'];
    final d = call.data;
    if (call.domain == 'scene' && call.service == 'create') {
      final sceneId = 'scene.${d['scene_id']}';
      final members = (d['snapshot_entities']! as List<Object?>).cast<String>();
      sceneMembers[sceneId] = {
        for (final m in members)
          if (_states[m] != null) m: _states[m]!,
      };
      _states[sceneId] = HaState(
        entityId: sceneId,
        state: 'scening',
        attributes: {'entity_id': members},
      );
      return;
    }
    if (id is! String || !_states.containsKey(id)) {
      throw const PortException(
        PortErrorKind.notFound,
        'Nicht gefunden in Home Assistant.',
      );
    }
    switch ((call.domain, call.service)) {
      case ('scene', 'turn_on'):
        for (final m in (sceneMembers[id] ?? {}).values) {
          _states[m.entityId] = HaState(
            entityId: m.entityId,
            state: m.state,
            attributes: {..._states[m.entityId]!.attributes, ...m.attributes},
          );
        }
      case ('scene', 'delete'):
        _states.remove(id);
        sceneMembers.remove(id);
      case (_, 'turn_on') || (_, 'turn_off') || (_, 'toggle'):
        _power(id, call.service, d);
      case ('media_player', 'media_play'):
        set(id, 'playing');
      case ('media_player', 'media_pause'):
        set(id, 'paused');
      case ('media_player', 'media_stop'):
        set(id, 'idle');
      case ('media_player', 'media_play_pause'):
        set(id, _states[id]!.state == 'playing' ? 'paused' : 'playing');
      case ('media_player', 'volume_set'):
        set(id, _states[id]!.state, {'volume_level': d['volume_level']});
      case ('media_player', 'volume_up' || 'volume_down'):
        final v = (_states[id]!.attributes['volume_level'] as num?) ?? 0.5;
        set(id, _states[id]!.state, {
          'volume_level': (v + (call.service == 'volume_up' ? 0.1 : -0.1))
              .clamp(0, 1),
        });
      case ('media_player', 'volume_mute'):
        set(id, _states[id]!.state, {'is_volume_muted': d['is_volume_muted']});
      case ('media_player', 'media_next_track' || 'media_previous_track'):
        break;
      case ('climate', 'set_temperature'):
        set(id, _states[id]!.state, {
          for (final k in [
            'temperature',
            'target_temp_low',
            'target_temp_high',
          ])
            if (d[k] != null) k: d[k],
        });
      case ('climate', 'set_hvac_mode'):
        set(id, d['hvac_mode']! as String);
      case ('climate', 'set_preset_mode'):
        set(id, _states[id]!.state, {'preset_mode': d['preset_mode']});
      case ('lock', 'lock'):
        set(id, 'locked');
      case ('lock', 'unlock'):
        set(id, 'unlocked');
      case ('lock', 'open') || ('cover', 'open_cover'):
        set(id, 'open');
      case ('cover', 'close_cover'):
        set(id, 'closed');
      case ('cover', 'stop_cover'):
        break;
      case ('cover', 'set_cover_position'):
        _setCoverPosition(id, d['position']);
      case ('alarm_control_panel', final s):
        set(id, switch (s) {
          'alarm_disarm' => 'disarmed',
          'alarm_arm_home' => 'armed_home',
          'alarm_arm_away' => 'armed_away',
          _ => 'armed_night',
        });
      default:
        throw const PortException(
          PortErrorKind.failed,
          'Unerwartete Antwort von Home Assistant (HTTP 400).',
        );
    }
  }

  void _power(String id, String service, Map<String, Object?> d) {
    final cur = _states[id]!;
    final domain = cur.domain;
    if (domain == 'climate') {
      set(id, service == 'turn_off' ? 'off' : 'heat');
      return;
    }
    final on = switch (service) {
      'turn_on' => true,
      'turn_off' => false,
      _ => cur.state != 'on',
    };
    final attrs = <String, Object?>{};
    if (domain == 'light' && on) {
      if (d['brightness_pct'] is num) {
        attrs['brightness'] = ((d['brightness_pct']! as num) * 255 / 100)
            .round();
      }
      if (d['brightness'] is num) attrs['brightness'] = d['brightness'];
      if (d['rgb_color'] != null) attrs['rgb_color'] = d['rgb_color'];
      if (d['color_temp_kelvin'] != null) {
        attrs['color_temp_kelvin'] = d['color_temp_kelvin'];
        attrs['color_mode'] = 'color_temp';
      }
    }
    final String state;
    if (domain == 'media_player') {
      state = on ? (cur.state == 'off' ? 'idle' : cur.state) : 'off';
    } else {
      state = on ? 'on' : 'off';
    }
    set(id, state, attrs);
  }
}
