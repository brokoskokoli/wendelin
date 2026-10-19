import 'dart:async';

import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../l10n/gen/app_localizations.dart';
import '../l10n/gen/app_localizations_de.dart';
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

/// Persists the highest verified Tinfoil release per provider host and
/// router repo (K59). A damaged entry throws [FormatException]: the verifier
/// then refuses (fail-closed), it never counts as no floor.
final class SettingsReleaseFloorStore implements ReleaseFloorStore {
  /// Creates the store.
  const SettingsReleaseFloorStore(this._settings);

  final SettingsRepository _settings;

  @override
  Future<ReleaseFloor?> load(String profileId) async {
    final json = await _settings.get(AppSettings.releaseFloor(profileId));
    return json == null ? null : ReleaseFloor.fromJson(json);
  }

  @override
  Future<void> save(String profileId, ReleaseFloor floor) =>
      _settings.set(AppSettings.releaseFloor(profileId), floor.toJson());
}

/// Keeps the live TEE providers of the app (one per profile): merges their
/// results (the GPU mode belongs to the profile, WP82), warns about a failed
/// asynchronous GPU check and offers „neu prüfen“, „ohne GPU-Prüfung
/// senden“ and the warm-up at app start.
final class AttestationHub {
  /// Creates the hub.
  AttestationHub({
    required this.notifier,
    String Function(String profileId)? nameOf,
    AppLocalizations Function()? texts,
  }) : _nameOf = nameOf ?? ((id) => id),
       _texts = texts ?? AppLocalizationsDe.new;

  /// System notifications.
  final AttestationNotifier notifier;

  final String Function(String profileId) _nameOf;

  /// Texts in the current app language (read when a notification is shown).
  final AppLocalizations Function() _texts;
  final Map<String, AttestedProvider> _providers = {};
  final Map<String, StreamSubscription<AttestationReport>> _subs = {};
  final StreamController<ProfileReport> _reports =
      StreamController<ProfileReport>.broadcast();

  /// All results of all TEE providers.
  Stream<ProfileReport> get reports => _reports.stream;

  /// GPU mode of the live provider of [profileId] (`off` if there is none).
  GpuCheckMode modeOf(String profileId) =>
      _providers[profileId]?.gpuMode ?? GpuCheckMode.off;

  /// Takes over [provider] of [profileId]; an earlier one is dropped.
  ///
  /// [reason] says why it was built (goes to the log line of the adoption).
  void register(String profileId, AttestedProvider provider, {String? reason}) {
    unawaited(_subs.remove(profileId)?.cancel());
    // A rebuilt provider of the same profile (profile list or rules changed)
    // takes over the session its predecessor verified completely instead of
    // attesting again (WP77); only for an unchanged endpoint.
    final previous = _providers[profileId];
    if (previous != null) provider.adoptSessionOf(previous, reason: reason);
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

  /// Prepares [profileId] in the background (app start, overlay start):
  /// attests unless it is locked or has a valid session, fetches the GPU
  /// evidence and opens the connection. Never throws.
  Future<void> warmUp(String profileId) async {
    final p = _providers[profileId];
    if (p == null || p.locked) return;
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
    if (gpu && modeOf(profileId) == GpuCheckMode.after) {
      unawaited(
        notifier.show(
          title: _texts().gpuNotifyFailedTitle,
          text: _texts().gpuNotifyFailedText(_nameOf(profileId)),
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
