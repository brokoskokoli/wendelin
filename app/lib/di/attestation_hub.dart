import 'dart:async';

import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../platform/channel_notifier.dart';
import 'app_settings.dart';
import 'provider_config.dart';

/// A result of a TEE provider, with the profile it belongs to.
typedef ProfileReport = ({String profileId, AttestationReport report});

/// [AttestationPinStore] over the settings (one JSON setting per profile).
final class SettingsAttestationPinStore implements AttestationPinStore {
  /// Creates the store.
  const SettingsAttestationPinStore(this._settings);

  final SettingsRepository _settings;

  @override
  Future<AttestationPin?> load(String profileId) async {
    try {
      final json = await _settings.get(AppSettings.attestationPin(profileId));
      return json == null ? null : AttestationPin.fromJson(json);
    } on FormatException {
      return null; // A damaged pin counts as no pin: the next check sets it.
    }
  }

  @override
  Future<void> save(String profileId, AttestationPin pin) =>
      _settings.set(AppSettings.attestationPin(profileId), pin.toJson());
}

/// Keeps the live TEE providers of the app (one per profile): applies the
/// GPU mode to all of them, merges their results, warns about a failed
/// asynchronous GPU check and offers „neu prüfen“, „ohne GPU-Prüfung
/// senden“ and the warm-up at app start.
final class AttestationHub {
  /// Creates the hub with the GPU mode [gpuMode] at start.
  AttestationHub({
    required this.notifier,
    GpuCheckMode gpuMode = GpuCheckMode.off,
    String Function(String profileId)? nameOf,
  }) : _mode = gpuMode,
       _nameOf = nameOf ?? ((id) => id);

  /// System notifications.
  final AttestationNotifier notifier;

  final String Function(String profileId) _nameOf;
  final Map<String, AttestedProvider> _providers = {};
  final Map<String, StreamSubscription<AttestationReport>> _subs = {};
  final StreamController<ProfileReport> _reports =
      StreamController<ProfileReport>.broadcast();
  GpuCheckMode _mode;

  /// All results of all TEE providers.
  Stream<ProfileReport> get reports => _reports.stream;

  /// Current GPU mode.
  GpuCheckMode get gpuMode => _mode;

  /// Changes the GPU mode of all providers (and of those created later).
  set gpuMode(GpuCheckMode mode) {
    _mode = mode;
    for (final p in _providers.values) {
      p.gpuMode = mode;
    }
  }

  /// Takes over [provider] of [profileId]; an earlier one is dropped.
  void register(String profileId, AttestedProvider provider) {
    unawaited(_subs.remove(profileId)?.cancel());
    provider.gpuMode = _mode;
    _providers[profileId] = provider;
    _subs[profileId] = provider.reports.listen((r) => _onReport(profileId, r));
  }

  /// The provider of [profileId], if it is attested.
  AttestedProvider? provider(String profileId) => _providers[profileId];

  /// Whether [profileId] refuses requests until [reattest].
  bool isLocked(String profileId) => _providers[profileId]?.locked ?? false;

  /// Lifts the lock and attests [profileId] again.
  Future<AttestationReport?> reattest(String profileId) =>
      _providers[profileId]?.reattest() ?? Future.value();

  /// The next request to [profileId] goes out although the GPU check failed
  /// (valid once, user choice).
  void allowWithoutGpuCheck(String profileId) =>
      _providers[profileId]?.allowNextRequestWithoutGpuCheck();

  /// Attests [profileId] in the background (app start), unless it is locked
  /// or has a valid session. Never throws.
  Future<void> warmUp(String profileId) async {
    final p = _providers[profileId];
    if (p == null || p.locked || p.session != null) return;
    try {
      await p.warmUp();
    } on Object {
      // The first request attests again and reports the problem.
    }
  }

  void _onReport(String profileId, AttestationReport report) {
    _reports.add((profileId: profileId, report: report));
    final gpu =
        report.reasonCode == 'gpu_failed' ||
        report.reasonCode == 'gpu_unavailable';
    if (gpu && _mode == GpuCheckMode.after) {
      unawaited(
        notifier.show(
          title: 'GPU-Prüfung fehlgeschlagen',
          text:
              'Die GPU-Prüfung der letzten Antwort von ${_nameOf(profileId)} '
              'ist fehlgeschlagen. Die nächste Anfrage prüft vorher. '
              'Details im Prüfprotokoll.',
        ),
      );
    }
  }

  /// Stops listening.
  Future<void> dispose() async {
    for (final s in _subs.values) {
      await s.cancel();
    }
    _subs.clear();
    await _reports.close();
  }
}

/// App start: attests the default provider in the background if it is a
/// TEE provider and the device is online, so the first request does not wait
/// for the check. Never throws.
Future<void> warmUpAttestation({
  required Future<ProviderConfig?> config,
  required NetworkStatus network,
  required AttestationHub hub,
}) async {
  try {
    final c = await config;
    if (c == null || network.current == NetworkState.offline) return;
    await hub.warmUp(c.primary.profileId);
  } on Object {
    // Optional optimization; the first request attests again.
  }
}
