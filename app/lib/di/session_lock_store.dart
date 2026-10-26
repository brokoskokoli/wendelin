import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import 'app_settings.dart';
import 'session_manager.dart';

/// Keeps the session locks of the risk policy in the settings (WP157,
/// ADR 0023), so a locked conversation stays locked after an engine rebuild
/// and an app restart. A damaged entry throws [FormatException]: the policy
/// then denies every `external` tool (fail-closed), it never counts as no
/// lock.
final class SettingsSessionLockStore implements SessionLockStore {
  /// Creates the store.
  const SettingsSessionLockStore(this._settings);

  final SettingsRepository _settings;

  @override
  Future<Map<String, String>> load() async {
    final json = await _settings.get(AppSettings.sessionLocks);
    if (json == null) return const {};
    return {
      for (final e in json.entries)
        e.key: e.value is String
            ? e.value! as String
            : throw const FormatException('Sitzungssperre: Profil-Id'),
    };
  }

  @override
  Future<void> save(Map<String, String> locks) => locks.isEmpty
      ? _settings.remove(AppSettings.sessionLocks)
      : _settings.set(AppSettings.sessionLocks, {...locks});
}

/// [AbsenceStamp] in the settings (epoch milliseconds).
final class SettingsAbsenceStamp implements AbsenceStamp {
  /// Creates the stamp.
  const SettingsAbsenceStamp(this._settings);

  final SettingsRepository _settings;

  @override
  Future<DateTime?> load() async {
    final ms = await _settings.get(AppSettings.backgroundSince);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  @override
  Future<void> save(DateTime? at) => at == null
      ? _settings.remove(AppSettings.backgroundSince)
      : _settings.set(AppSettings.backgroundSince, at.millisecondsSinceEpoch);
}
