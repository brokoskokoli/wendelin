import 'package:flutter/services.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'channels.dart';

export 'channels.dart' show torchChannelName;

/// [TorchPort] over `CameraManager.setTorchMode` (Kotlin `TorchChannel`).
/// Needs no camera permission.
final class ChannelTorchPort implements TorchPort {
  /// Creates the port; [channel] is injectable for tests.
  const ChannelTorchPort({
    this._channel = const MethodChannel(torchChannelName),
  });

  final MethodChannel _channel;

  @override
  Future<bool> isAvailable() async =>
      await _call<bool>('isAvailable', null) ?? false;

  @override
  Future<bool> state() async => await _call<bool>('state', null) ?? false;

  @override
  Future<void> set(bool on) => _call<void>('set', {'on': on});

  Future<T?> _call<T>(String method, Object? args) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw switch (e.code) {
        'no_led' => const PortException(
          PortErrorKind.unsupported,
          'Dieses Gerät hat keine Taschenlampe (Blitz-LED).',
        ),
        'camera_in_use' => const PortException(
          PortErrorKind.unavailable,
          'Die Taschenlampe geht gerade nicht, die Kamera ist belegt.',
        ),
        _ => const PortException(
          PortErrorKind.unavailable,
          'Die Taschenlampe geht gerade nicht '
          '(z. B. zu warm oder vom System gesperrt).',
        ),
      };
    } on MissingPluginException {
      throw const PortException(
        PortErrorKind.unsupported,
        'Die Taschenlampe lässt sich hier nicht schalten.',
      );
    }
  }
}
