import 'package:flutter/services.dart';

import 'channels.dart';

export 'channels.dart' show notifyChannelName;

/// Shows a system notification for a failed TEE check after the answer
/// (WP52). Content is never part of it: only a short, fixed text.
abstract interface class AttestationNotifier {
  /// Whether notifications are allowed.
  Future<bool> hasPermission();

  /// Asks for the permission (Android 13+); `true` if granted.
  Future<bool> requestPermission();

  /// Posts a notification; `false` if it was not shown (no permission).
  Future<bool> show({required String title, required String text});
}

/// [AttestationNotifier] over the Kotlin `NotifyChannel`.
final class ChannelAttestationNotifier implements AttestationNotifier {
  /// Creates the notifier; [channel] is injectable for tests.
  const ChannelAttestationNotifier({
    this._channel = const MethodChannel(notifyChannelName),
  });

  final MethodChannel _channel;

  @override
  Future<bool> hasPermission() => _call('hasPermission', null);

  @override
  Future<bool> requestPermission() => _call('requestPermission', null);

  @override
  Future<bool> show({required String title, required String text}) =>
      _call('show', {'title': title, 'text': text});

  Future<bool> _call(String method, Object? args) async {
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

/// Notifier that shows nothing (tests, platforms without notifications).
final class NoopAttestationNotifier implements AttestationNotifier {
  /// Creates the notifier.
  const NoopAttestationNotifier();

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<bool> show({required String title, required String text}) async =>
      false;
}
