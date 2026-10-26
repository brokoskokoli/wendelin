import 'package:wendelin_core/wendelin_core.dart';

import 'ha_context.dart';
import 'ha_model.dart';
import 'ha_policy.dart';

/// Domains the fast path may touch (WP135 D): lights, switches, quiet
/// blinds and thermostats. Never locks, alarm panels, garage/gate/door
/// covers, scenes or media players, and no device whose name or entity id
/// holds a blocker word ([HaWords.blockers]), whatever its domain.
const _fastDomains = {'light', 'switch', 'cover', 'climate'};

/// The fast path of Home Assistant (WP135 D): recognizes simple requests
/// such as „Küche Deckenlicht aus“ or „Rollo Wohnzimmer auf 50 Prozent“
/// without a model and hands the same `ha__call` the model would have made
/// to the agent, which runs it through the normal tool path (executor,
/// history, undo, audit, fixed confirmation sentence).
///
/// As strict as `matchLockedCommand`:
/// - **Every** word must be known: filler, request verb or politeness, an
///   action word, a device type word, a number with its unit, or a word of
///   the device's name or room. One unknown word („nicht“, „und“, „ist“,
///   a question) gives `null` and the model answers.
/// - Exactly one action (or one number with a unit), exactly one device:
///   found by name, or by room and type; several candidates or none give
///   `null`. A bare „Licht an“ without room or name goes to the model even
///   if there is only one light (decision of the maintainer).
/// - Never: locks, alarm panels, scenes, media players, garage/gate/door
///   covers or covers without the option „ohne Rückfrage“ and a blind
///   class, devices marked „always confirm“, devices Home Assistant no
///   longer lists. The call itself checks the live state again
///   ([HaCallDeviceTool]).
final class HaFastPath implements FastPath {
  /// Creates the fast path on [ctx].
  const HaFastPath(this.ctx);

  /// Approved devices and the Home Assistant access.
  final HaContext ctx;

  @override
  Future<FastPathCall?> match(String text, {required String? language}) async {
    try {
      return await _match(text, language);
    } on Object {
      // Fail-closed: whatever goes wrong, the model answers.
      return null;
    }
  }

  Future<FastPathCall?> _match(String text, String? language) async {
    // A question is no command („Küche Licht an?“): the model answers.
    if (text.contains('?')) return null;
    final code = (language ?? '').toLowerCase().split(RegExp('[-_]')).first;
    final words = haWordsByLanguage[code];
    if (words == null) return null;
    final eligible = [
      for (final e in await ctx.approved())
        if (_fastDomains.contains(e.domain) &&
            !e.alwaysConfirm &&
            !haHasBlocker('${e.name} ${e.entityId}'))
          e,
    ];
    if (eligible.isEmpty) return null;

    final tokens = _tokens(text, words);
    if (tokens.isEmpty) return null;
    final used = List<bool>.filled(tokens.length, false);

    final actions = _consumeActions(tokens, used, words);
    final (:value, :unit, :ok) = _consumeNumber(tokens, used, words);
    if (!ok) return null;
    _consume(tokens, used, {
      ...words.fillers.map(_fold),
      ...words.neutral.map(_fold),
    });
    final domains = _consumeTypes(tokens, used, words);

    final nameWords = [
      for (var i = 0; i < tokens.length; i++)
        if (!used[i]) tokens[i],
    ];
    // „Licht an“ without room or name: the model decides.
    if (nameWords.isEmpty) return null;

    final matches = [
      for (final e in eligible)
        if ((domains.isEmpty || domains.contains(e.domain)) &&
            _wordsOf(e).containsAll(nameWords) &&
            // A room word alone is no device: a name or type word is needed.
            (domains.isNotEmpty || nameWords.any(_nameWordsOf(e).contains)))
          e,
    ];
    if (matches.length != 1) return null;
    final e = matches.single;

    final half = actions.contains(HaAction.half);
    final rest = {...actions}..remove(HaAction.half);
    if (value != null && half) return null;
    final call = switch (e.domain) {
      'light' => _light(rest, half, value, unit),
      'switch' => _onOff(rest, half, value, unit),
      'cover' => _cover(e, rest, half, value, unit),
      'climate' => _climate(rest, half, value, unit),
      _ => null,
    };
    if (call == null) return null;
    return FastPathCall(
      tool: 'ha__call',
      arguments: {'entity': e.entityId, ...call},
    );
  }

  Map<String, Object?>? _light(
    Set<HaAction> a,
    bool half,
    num? value,
    _Unit? unit,
  ) {
    if (half) return null;
    if (value != null) {
      const allowed = {
        HaAction.on,
        HaAction.open,
        HaAction.dimmer,
        HaAction.brighter,
      };
      if (unit != _Unit.percent || !allowed.containsAll(a)) return null;
      final pct = _percent(value);
      if (pct == null || pct < 1) return null;
      return {'service': 'turn_on', 'brightness_pct': pct};
    }
    return _service(a, const {
      HaAction.on: 'turn_on',
      HaAction.off: 'turn_off',
    });
  }

  Map<String, Object?>? _onOff(
    Set<HaAction> a,
    bool half,
    num? value,
    _Unit? unit,
  ) {
    if (half || value != null) return null;
    return _service(a, const {
      HaAction.on: 'turn_on',
      HaAction.off: 'turn_off',
    });
  }

  Map<String, Object?>? _cover(
    HaEntity e,
    Set<HaAction> a,
    bool half,
    num? value,
    _Unit? unit,
  ) {
    // Only blinds the user let move without a question (WP135 E). The call
    // checks the live class again.
    if (!e.noConfirm || !haQuietCoverClasses.contains(e.deviceClass)) {
      return null;
    }
    if (value != null || half) {
      // „auf“ is both „open“ and the preposition of „auf 50 Prozent“, fr
      // „mets“ both „on“ and „set“: the number decides.
      if (!_valueVerbs.containsAll(a)) return null;
      final pct = half ? 50 : (unit == _Unit.percent ? _percent(value!) : null);
      if (pct == null) return null;
      return {'service': 'set_cover_position', 'position_pct': pct};
    }
    return _service(a, const {
      HaAction.open: 'open_cover',
      HaAction.close: 'close_cover',
      HaAction.stop: 'stop_cover',
    });
  }

  Map<String, Object?>? _climate(
    Set<HaAction> a,
    bool half,
    num? value,
    _Unit? unit,
  ) {
    if (half) return null;
    if (value != null) {
      if (unit != _Unit.degrees || !_valueVerbs.containsAll(a)) {
        return null;
      }
      if (value < 5 || value > 35) return null;
      return {'service': 'set_temperature', 'temperature': '$value'};
    }
    return _service(a, const {
      HaAction.on: 'turn_on',
      HaAction.off: 'turn_off',
    });
  }

  /// The service for exactly one action out of [table], else `null`.
  Map<String, Object?>? _service(Set<HaAction> a, Map<HaAction, String> table) {
    if (a.length != 1) return null;
    final service = table[a.single];
    return service == null ? null : {'service': service};
  }

  int? _percent(num v) => v is int && v >= 0 && v <= 100 ? v : null;

  /// Words of the device name only, folded.
  Set<String> _nameWordsOf(HaEntity e) => _fold(e.name).split(' ').toSet();

  /// Words of the device name and room, folded.
  Set<String> _wordsOf(HaEntity e) =>
      _fold('${e.name} ${e.area ?? ''}').split(' ').toSet();

  /// The folded words of [text]; `%`, `°` and decimals are prepared so that
  /// the folding does not tear them apart („21,5“ → `21x5`).
  List<String> _tokens(String text, HaWords w) {
    final prepared = text
        .replaceAllMapped(RegExp(r'(\d)[.,](\d)'), (m) => '${m[1]}x${m[2]}')
        .replaceAll('%', ' ${w.percent.first} ')
        .replaceAll('°', ' ${w.degrees.first} ');
    final folded = _fold(prepared);
    return folded.isEmpty ? const [] : folded.split(' ');
  }

  /// Marks the words of every action phrase (longest first) and returns the
  /// actions found. Words are consumed as whole phrases, so a part of a
  /// phrase („nicht“ of „nicht weiter“) is never an action on its own.
  Set<HaAction> _consumeActions(
    List<String> tokens,
    List<bool> used,
    HaWords w,
  ) {
    final phrases = [
      for (final MapEntry(:key, :value) in w.actions.entries)
        for (final p in value)
          if (_fold(p).isNotEmpty) (key, _fold(p).split(' ')),
    ]..sort((a, b) => b.$2.length.compareTo(a.$2.length));
    final found = <HaAction>{};
    for (final (action, parts) in phrases) {
      for (var i = 0; i + parts.length <= tokens.length; i++) {
        var ok = true;
        for (var j = 0; j < parts.length && ok; j++) {
          ok = !used[i + j] && tokens[i + j] == parts[j];
        }
        if (!ok) continue;
        for (var j = 0; j < parts.length; j++) {
          used[i + j] = true;
        }
        found.add(action);
      }
    }
    return found;
  }

  /// A number directly followed by a percent or degree word. At most one
  /// (`ok` is `false` for more).
  ({num? value, _Unit? unit, bool ok}) _consumeNumber(
    List<String> tokens,
    List<bool> used,
    HaWords w,
  ) {
    num? value;
    _Unit? unit;
    final units = <(_Unit, List<String>)>[
      for (final p in w.percent) (_Unit.percent, _fold(p).split(' ')),
      for (final d in w.degrees) (_Unit.degrees, _fold(d).split(' ')),
    ]..sort((a, b) => b.$2.length.compareTo(a.$2.length));
    final number = RegExp(r'^(\d{1,3})(?:x(\d))?$');
    for (var i = 0; i < tokens.length; i++) {
      final m = used[i] ? null : number.firstMatch(tokens[i]);
      if (m == null) continue;
      for (final (kind, parts) in units) {
        var ok = i + parts.length < tokens.length;
        for (var j = 0; j < parts.length && ok; j++) {
          ok = !used[i + 1 + j] && tokens[i + 1 + j] == parts[j];
        }
        if (!ok) continue;
        if (value != null) return (value: null, unit: null, ok: false);
        value = num.parse(m[2] == null ? m[1]! : '${m[1]}.${m[2]}');
        unit = kind;
        for (var j = 0; j <= parts.length; j++) {
          used[i + j] = true;
        }
        break;
      }
    }
    return (value: value, unit: unit, ok: true);
  }

  void _consume(List<String> tokens, List<bool> used, Set<String> known) {
    for (var i = 0; i < tokens.length; i++) {
      if (!used[i] && known.contains(tokens[i])) used[i] = true;
    }
  }

  /// Marks type words (stems, recognition slips) and returns their domains.
  Set<String> _consumeTypes(List<String> tokens, List<bool> used, HaWords w) {
    final domains = <String>{};
    for (final MapEntry(:key, :value) in w.types.entries) {
      final stems = [
        ...value,
        ...?w.recognitionErrors[key],
      ].map(_fold).where((s) => s.isNotEmpty && !s.contains(' '));
      for (var i = 0; i < tokens.length; i++) {
        if (!used[i] && stems.any(tokens[i].startsWith)) {
          used[i] = true;
          domains.add(key);
        }
      }
    }
    return domains;
  }
}

/// Actions that may stand next to a value for a cover or thermostat.
const _valueVerbs = {HaAction.open, HaAction.on};

enum _Unit { percent, degrees }

/// [foldForMatch] with apostrophes removed, so „Anna's Licht“ and
/// „Anna’s Licht“ equal „Annas Licht“ (WP150).
String _fold(String s) => foldForMatch(s.replaceAll(RegExp("['’‘`´]"), ''));
