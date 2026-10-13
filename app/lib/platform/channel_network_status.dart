import 'package:flutter/services.dart';
import 'package:wendelin_agent/wendelin_agent.dart';

/// Name of the platform channel for the connectivity (Kotlin:
/// `NetworkChannel.kt`).
const networkChannelName = 'app.wendelin/network';

/// [NetworkStatus] from Android's `ConnectivityManager` (no Play
/// Services): the Kotlin side answers `state` and pushes `changed` when the
/// default network changes. [current] is the last known state, so the
/// router can read it synchronously.
///
/// Until the first answer, and where the channel is missing (tests,
/// other platforms), the state is [NetworkState.online], the behaviour
/// before routing rules existed.
final class ChannelNetworkStatus implements NetworkStatus {
  /// Creates the status; [channel] is injectable for tests.
  ChannelNetworkStatus({
    this._channel = const MethodChannel(networkChannelName),
  });

  final MethodChannel _channel;
  NetworkState _current = NetworkState.online;

  @override
  NetworkState get current => _current;

  /// Listens for changes and asks for the current state.
  Future<void> start() async {
    _channel.setMethodCallHandler(_handle);
    await refresh();
  }

  /// Asks the platform for the current state; on errors the last known
  /// state stays.
  Future<void> refresh() async {
    try {
      _current =
          parse(await _channel.invokeMethod<String>('state')) ?? _current;
    } on PlatformException {
      // Keep the last known state: the router must not fail on this.
    } on MissingPluginException {
      // No platform side (tests, desktop): stays online.
    }
  }

  /// Stops listening.
  void dispose() => _channel.setMethodCallHandler(null);

  Future<Object?> _handle(MethodCall call) async {
    if (call.method == 'changed') {
      _current = parse(call.arguments) ?? _current;
      return null;
    }
    throw MissingPluginException(call.method);
  }

  /// The state named [value] (`offline`, `online`, `metered`), else `null`.
  static NetworkState? parse(Object? value) => switch (value) {
    'offline' => NetworkState.offline,
    'online' => NetworkState.online,
    'metered' => NetworkState.metered,
    _ => null,
  };
}
