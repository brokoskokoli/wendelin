part of 'spotify_session.dart';

/// Device discovery of [SpotifySession] (kept apart for size).
extension _SpotifyDevices on SpotifySession {
  Future<List<SpotifyDevice>> _usable() async => [
    for (final d in await run(api.devices))
      if (!d.isRestricted) d,
  ];

  Future<bool> _wake() async => launcher != null && await launcher!.wake();

  Future<({SpotifyDevice device, String via})?> _waitForPhone() async {
    for (var i = 0; i < SpotifySession.wakeAttempts; i++) {
      await _delay(SpotifySession.wakeInterval);
      final found = await _phone(await _usable());
      if (found != null) return found;
    }
    return null;
  }

  static SpotifyDevice? _byName(List<SpotifyDevice> devices, String name) {
    final wanted = name.trim().toLowerCase();
    if (wanted.isEmpty) return null;
    for (final d in devices) {
      if (d.name.trim().toLowerCase() == wanted) return d;
    }
    for (final d in devices) {
      if (d.name.toLowerCase().contains(wanted)) return d;
    }
    return null;
  }

  /// The phone's device among [usable]: the remembered id, a name of the
  /// phone, or the only smartphone.
  Future<({SpotifyDevice device, String via})?> _phone(
    List<SpotifyDevice> usable,
  ) async {
    ({SpotifyDevice device, String via})? found;
    final cached = usable.where((d) => d.id == _phoneId).firstOrNull;
    if (cached != null) {
      found = (device: cached, via: 'cache');
    } else {
      Set<String> names = const {};
      try {
        names = {
          for (final n in await hostDevice?.names() ?? const <String>{})
            n.trim().toLowerCase(),
        }..remove('');
      } on Object {
        // Names are optional help; the type rule still applies.
      }
      final byName = usable
          .where((d) => names.contains(d.name.trim().toLowerCase()))
          .firstOrNull;
      if (byName != null) {
        found = (device: byName, via: 'name');
      } else {
        final phones = usable
            .where((d) => d.type?.toLowerCase() == 'smartphone')
            .toList();
        if (phones.length == 1) found = (device: phones.single, via: 'type');
      }
    }
    // Only a name match is remembered: the type rule is a guess.
    if (found != null && found.via != 'type') _phoneId = found.device.id;
    return found;
  }

  /// The usable non-phone device that plays right now, else `null`.
  ///
  /// Spotify may report `is_playing` for a dead device, so the position must
  /// grow between two reads [SpotifyPlaybackVerifier.interval] apart
  /// (`skip=stalled` otherwise). Read errors (except auth) mean `null`.
  Future<SpotifyDevice?> _playingElsewhere(
    List<SpotifyDevice> usable,
    String? phoneId,
  ) async {
    final first = await _readPlayback();
    final device = first == null ? null : _deviceOf(first, usable);
    if (device == null || device.id == phoneId) return null;
    await _delay(SpotifySession.verifyInterval);
    final second = await _readPlayback();
    final p1 = first!.progressMs;
    final p2 = second?.progressMs;
    if (second == null ||
        !second.isPlaying ||
        _deviceOf(second, usable)?.id != device.id ||
        p1 == null ||
        p2 == null ||
        p2 <= p1) {
      onDiagnostic?.call('spotify-device', {'skip': 'stalled'});
      return null;
    }
    return device;
  }

  /// The state if something plays, else `null` (also on read errors other
  /// than auth, which are rethrown).
  Future<SpotifyPlayback?> _readPlayback() async {
    try {
      final state = await run(api.playback);
      return state != null && state.isPlaying ? state : null;
    } on PortException catch (e) {
      if (e.kind == PortErrorKind.permissionDenied) rethrow;
      return null;
    }
  }

  /// The usable device [state] plays on: by id, else (id `null`) by name.
  static SpotifyDevice? _deviceOf(
    SpotifyPlayback state,
    List<SpotifyDevice> usable,
  ) {
    final id = state.deviceId;
    if (id != null) return usable.where((d) => d.id == id).firstOrNull;
    final name = state.deviceName?.trim().toLowerCase();
    if (name == null || name.isEmpty) return null;
    return usable.where((d) => d.name.trim().toLowerCase() == name).firstOrNull;
  }

  /// Sends the command to the playing foreign device [target] and checks
  /// it; `null` if nothing arrived there (the caller falls back to the
  /// phone). Only dead-device errors count as "nothing arrived".
  Future<SpotifyStart?> _playOnActive(
    Future<void> Function(SpotifyAuth auth, String deviceId) op,
    SpotifyDevice target,
    String? fellBackFrom,
  ) async {
    try {
      await run((a) => op(a, target.id));
      final verdict = await _verifier.check(target, false);
      if (verdict == SpotifyVerdict.unchecked ||
          verdict == SpotifyVerdict.playing) {
        return (
          deviceId: target.id,
          deviceName: target.name,
          isPhone: false,
          confirmed: verdict == SpotifyVerdict.playing,
          fellBackFrom: fellBackFrom,
        );
      }
    } on PortException catch (e) {
      if (!SpotifySession._deadDevice(e)) rethrow;
    }
    onDiagnostic?.call('spotify-device', {'fallback': true});
    return null;
  }
}
