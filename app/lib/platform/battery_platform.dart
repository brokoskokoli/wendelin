import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'channels.dart';

export 'channels.dart' show batteryChannelName;

/// Bridge to battery and power management (overridden in tests). Reused by
/// the wake-word service (WP50).
final batteryPlatformProvider = Provider<BatteryPlatform>(
  (ref) => BatteryPlatform(),
);

/// App standby bucket of Android (`UsageStatsManager`); `rare` and
/// `restricted` delay or block background starts.
enum StandbyBucket {
  /// Used recently.
  active,

  /// Used regularly.
  workingSet,

  /// Used from time to time.
  frequent,

  /// Rarely used: jobs and starts are limited.
  rare,

  /// Restricted by the system or the user.
  restricted,

  /// Never used since install / unknown to the system.
  never;

  /// Parses the Kotlin name (`working_set`, …); `null` if unknown.
  static StandbyBucket? parse(Object? name) => switch (name) {
    'active' => active,
    'working_set' => workingSet,
    'frequent' => frequent,
    'rare' => rare,
    'restricted' => restricted,
    'never' => never,
    _ => null,
  };

  /// Whether Android limits background starts in this bucket.
  bool get limited => this == rare || this == restricted;
}

/// What is known about power management (WP56).
class BatteryStatus {
  /// Creates a status.
  const BatteryStatus({
    this.ignoringOptimizations = true,
    this.bucket,
    this.vendor,
    this.vendorSettings = false,
  });

  /// Reads the answer of the `status` call; unknown values give the
  /// harmless defaults (no hint).
  factory BatteryStatus.fromChannel(Object? raw) {
    if (raw is! Map) return const BatteryStatus();
    return BatteryStatus(
      ignoringOptimizations: raw['ignoring'] != false,
      bucket: StandbyBucket.parse(raw['bucket']),
      vendor: raw['vendor'] is String ? raw['vendor'] as String : null,
      vendorSettings: raw['vendorSettings'] == true,
    );
  }

  /// Whether Android exempts Wendelin from battery optimization.
  final bool ignoringOptimizations;

  /// App standby bucket, `null` if unknown.
  final StandbyBucket? bucket;

  /// `xiaomi`, `samsung`, `oneplus`, `huawei`; `null` for stock Android.
  final String? vendor;

  /// Whether a settings page of the vendor can be opened by intent.
  final bool vendorSettings;

  /// Whether anything is worth showing.
  bool get hasHints =>
      !ignoringOptimizations || (bucket?.limited ?? false) || vendor != null;
}

/// Battery optimization, standby bucket and vendor settings.
class BatteryPlatform {
  /// Creates the bridge; `channel` is injectable for tests.
  BatteryPlatform({this._channel = const MethodChannel(batteryChannelName)});

  final MethodChannel _channel;

  /// Current state; harmless defaults where unknown.
  Future<BatteryStatus> status() async =>
      BatteryStatus.fromChannel(await _invoke<Object?>('status'));

  /// Asks the system to exempt Wendelin from battery optimization (system
  /// dialog; falls back to the list). `false` if no page opened.
  Future<bool> requestIgnoreOptimizations() async =>
      await _invoke<bool>('requestIgnoreOptimizations') ?? false;

  /// Opens the system battery settings of the app.
  Future<bool> openBatterySettings() async =>
      await _invoke<bool>('openBatterySettings') ?? false;

  /// Opens the vendor's autostart / battery page, `false` if none.
  Future<bool> openVendorSettings() async =>
      await _invoke<bool>('openVendorSettings') ?? false;

  Future<T?> _invoke<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
