import 'package:flutter/services.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'channels.dart';

export 'channels.dart' show locationChannelName;

/// [LocationPort] over `LocationManager` (Kotlin `LocationChannel`). Reads
/// the position once on request, foreground only. Errors carry no
/// coordinates and no place names.
final class ChannelLocationPort implements LocationPort {
  /// Creates the port; [channel] is injectable for tests.
  const ChannelLocationPort({
    this._channel = const MethodChannel(locationChannelName),
  });

  final MethodChannel _channel;

  @override
  Future<bool> hasPermission() async =>
      await _call<bool>('hasPermission', null) ?? false;

  @override
  Future<bool> requestPermission() async =>
      await _call<bool>('requestPermission', null) ?? false;

  @override
  Future<GeoFix> current() async {
    final raw = await _call<Map<Object?, Object?>>('current', null);
    final lat = raw?['latitude'];
    final lon = raw?['longitude'];
    if (lat is! num || lon is! num) {
      throw const PortException(
        PortErrorKind.unavailable,
        'Gerade kein Standort verfügbar.',
      );
    }
    final accuracy = raw?['accuracyM'];
    final place = raw?['place'];
    return GeoFix(
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      accuracyMeters: accuracy is num ? accuracy.toDouble() : null,
      placeName: place is String && place.isNotEmpty ? place : null,
    );
  }

  Future<T?> _call<T>(String method, Object? args) =>
      _invoke<T>(_channel, method, args);
}

/// [MapsLauncherPort] over `ACTION_VIEW` intents (Kotlin `LocationChannel`,
/// which only starts map intents).
final class ChannelMapsLauncherPort implements MapsLauncherPort {
  /// Creates the port; [channel] is injectable for tests.
  const ChannelMapsLauncherPort({
    this._channel = const MethodChannel(locationChannelName),
  });

  final MethodChannel _channel;

  @override
  Future<void> launch(MapsLaunch launch) => _call<void>('launch', {
    'uri': launch.uri.toString(),
    'package': ?launch.package,
  });

  Future<T?> _call<T>(String method, Object? args) =>
      _invoke<T>(_channel, method, args);
}

Future<T?> _invoke<T>(
  MethodChannel channel,
  String method,
  Object? args,
) async {
  try {
    return await channel.invokeMethod<T>(method, args);
  } on PlatformException catch (e) {
    throw switch (e.code) {
      'permissionDenied' => const PortException(
        PortErrorKind.permissionDenied,
        'Kein Zugriff auf den Standort. Bitte in den Einstellungen '
        'erlauben (Integrationen → Standort).',
      ),
      'unavailable' => const PortException(
        PortErrorKind.unavailable,
        'Gerade kein Standort verfügbar. Ist der Standort eingeschaltet?',
      ),
      'notFound' => const PortException(
        PortErrorKind.notFound,
        'Keine passende Karten-App gefunden.',
      ),
      _ => const PortException(
        PortErrorKind.failed,
        'Die Standortfunktion geht gerade nicht.',
      ),
    };
  } on MissingPluginException {
    throw const PortException(
      PortErrorKind.unsupported,
      'Standort und Karten gibt es hier nicht.',
    );
  }
}
