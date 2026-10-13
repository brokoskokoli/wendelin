import 'package:flutter/services.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// Name of the platform channel for the app detection (Kotlin:
/// `AppsChannel.kt`).
const appsChannelName = 'app.wendelin/apps';

/// [AppPresencePort] over `PackageManager.getPackageInfo` (Kotlin
/// `AppsChannel`). Only packages declared in `<queries>` of the manifest are
/// visible on Android 11+; all others are reported as missing.
final class ChannelAppPresencePort implements AppPresencePort {
  /// Creates the port; [channel] is injectable for tests.
  const ChannelAppPresencePort({
    this._channel = const MethodChannel(appsChannelName),
  });

  final MethodChannel _channel;

  @override
  Future<bool> isInstalled(String androidPackage) async {
    checkAndroidPackage(androidPackage);
    try {
      final installed = await _channel.invokeMethod<bool>('isInstalled', {
        'package': androidPackage,
      });
      return installed ?? false;
    } on PlatformException catch (e) {
      throw PortException(
        PortErrorKind.failed,
        'Installierte Apps lassen sich nicht prüfen (${e.code}).',
      );
    } on MissingPluginException {
      throw const PortException(
        PortErrorKind.unsupported,
        'Installierte Apps lassen sich hier nicht prüfen.',
      );
    }
  }
}
