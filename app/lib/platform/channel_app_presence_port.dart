import 'package:flutter/services.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'channels.dart';

export 'channels.dart' show appsChannelName;

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
      if (installed == null) {
        // A missing answer is no „not installed“: it would pause
        // integrations for nothing.
        throw const PortException(
          PortErrorKind.failed,
          'Installierte Apps lassen sich nicht prüfen (keine Antwort).',
        );
      }
      return installed;
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
