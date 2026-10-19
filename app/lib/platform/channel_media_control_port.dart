import 'package:flutter/services.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'channels.dart';

export 'channels.dart' show mediaChannelName;

/// [MediaControlPort] over `MediaSessionManager` (Kotlin `MediaChannel`).
/// Reading sessions and seeking need the notification access; transport
/// commands fall back to media key events without it.
final class ChannelMediaControlPort implements MediaControlPort {
  /// Creates the port; [channel] is injectable for tests.
  const ChannelMediaControlPort({
    this._channel = const MethodChannel(mediaChannelName),
  });

  final MethodChannel _channel;

  @override
  Future<bool> hasSessionAccess() async =>
      await _call<bool>('hasSessionAccess', null) ?? false;

  @override
  Future<void> openSessionAccessSettings() =>
      _call<void>('openSessionAccessSettings', null);

  @override
  Future<MediaSnapshot?> nowPlaying() async {
    final raw = await _call<Map<Object?, Object?>>('nowPlaying', null);
    if (raw == null) return null;
    final package = raw['package'];
    if (package is! String || package.isEmpty) return null;
    String? text(String key) {
      final v = raw[key];
      return v is String && v.isNotEmpty ? v : null;
    }

    int? number(String key) {
      final v = raw[key];
      return v is num && v >= 0 ? v.toInt() : null;
    }

    return MediaSnapshot(
      packageName: package,
      appName: text('app') ?? package,
      playing: raw['playing'] == true,
      title: text('title'),
      artist: text('artist'),
      album: text('album'),
      positionMs: number('positionMs'),
      durationMs: number('durationMs'),
    );
  }

  @override
  Future<void> send(MediaCommand command) =>
      _call<void>('send', {'command': command.name});

  @override
  Future<void> seekTo(Duration position) =>
      _call<void>('seekTo', {'positionMs': position.inMilliseconds});

  @override
  Future<void> openApp(String androidPackage, {String? searchQuery}) {
    checkAndroidPackage(androidPackage);
    return _call<void>('openApp', {
      'package': androidPackage,
      'query': ?searchQuery,
    });
  }

  Future<T?> _call<T>(String method, Object? args) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw switch (e.code) {
        'no_access' => const PortException(
          PortErrorKind.permissionDenied,
          'Dafür braucht Wendelin den Benachrichtigungszugriff '
          '(Einstellungen → Integrationen → Medien).',
        ),
        'no_session' => const PortException(
          PortErrorKind.notFound,
          'Gerade läuft nichts, das sich steuern ließe.',
        ),
        'not_seekable' => const PortException(
          PortErrorKind.unsupported,
          'Dieser Player lässt kein Spulen zu.',
        ),
        'not_installed' => const PortException(
          PortErrorKind.notFound,
          'Die App ist nicht installiert.',
        ),
        _ => const PortException(
          PortErrorKind.failed,
          'Die Mediensteuerung geht gerade nicht.',
        ),
      };
    } on MissingPluginException {
      throw const PortException(
        PortErrorKind.unsupported,
        'Die Mediensteuerung gibt es hier nicht.',
      );
    }
  }
}
