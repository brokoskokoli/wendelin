import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../redaction.dart';
import '../repositories/repositories.dart';
import 'database.dart';

/// Settings key holding the id of the default provider profile.
const defaultProfileSettingKey = 'providerProfiles.defaultId';

/// drift implementation of [ProviderProfileRepository].
final class DriftProviderProfileRepository
    implements ProviderProfileRepository {
  /// Creates the repository.
  DriftProviderProfileRepository(this._db);

  final WendelinDatabase _db;

  @override
  Future<void> save(ProviderProfile profile) async {
    _checkBaseUrl(profile.baseUrl);
    _checkNoSecretKeys(profile.extraHeaders, 'extraHeaders');
    _checkNoSecretKeys(profile.options, 'options');
    await _db
        .into(_db.providerProfiles)
        .insert(
          ProfileRow(id: profile.id, json: jsonEncode(profile.toJson())),
          onConflict: DoUpdate(
            (_) => ProviderProfilesCompanion(
              json: Value(jsonEncode(profile.toJson())),
            ),
          ),
        );
  }

  @override
  Future<ProviderProfile?> get(String id) async {
    final row = await (_db.select(
      _db.providerProfiles,
    )..where((p) => p.id.equals(id))).getSingleOrNull();
    return row == null ? null : _profile(row);
  }

  @override
  Future<List<ProviderProfile>> list() async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM provider_profiles ORDER BY rowid',
          readsFrom: {_db.providerProfiles},
        )
        .asyncMap(_db.providerProfiles.mapFromRow)
        .get();
    return rows.map(_profile).toList();
  }

  @override
  Future<bool> delete(String id) => _db.transaction(() async {
    final deleted = await (_db.delete(
      _db.providerProfiles,
    )..where((p) => p.id.equals(id))).go();
    if (await _defaultId() == id) {
      await (_db.delete(
        _db.settings,
      )..where((s) => s.key.equals(defaultProfileSettingKey))).go();
    }
    return deleted > 0;
  });

  @override
  Future<void> setDefault(String id) => _db.transaction(() async {
    if (await get(id) == null) {
      throw ArgumentError.value(id, 'id', 'unbekanntes Provider-Profil');
    }
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingRow(key: defaultProfileSettingKey, valueJson: jsonEncode(id)),
        );
  });

  @override
  Future<ProviderProfile?> defaultProfile() async {
    final id = await _defaultId();
    return id == null ? null : get(id);
  }

  Future<String?> _defaultId() async {
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(defaultProfileSettingKey))).getSingleOrNull();
    return row == null ? null : jsonDecode(row.valueJson) as String?;
  }

  static ProviderProfile _profile(ProfileRow r) =>
      ProviderProfile.fromJson(jsonDecode(r.json) as Map<String, Object?>);

  static void _checkBaseUrl(String? baseUrl) {
    if (baseUrl == null) return;
    final uri = Uri.tryParse(baseUrl);
    if (uri == null) return;
    if (uri.userInfo.isNotEmpty) {
      throw ArgumentError.value(
        'baseUrl',
        'profile',
        'enthält Zugangsdaten (user:pass@); Secrets gehören in den SecretStore',
      );
    }
    for (final k in uri.queryParametersAll.keys) {
      if (looksLikeSecretKey(k)) {
        throw ArgumentError.value(
          'baseUrl?$k',
          'profile',
          'sieht nach einem Secret aus; Secrets gehören in den SecretStore',
        );
      }
    }
  }

  static void _checkNoSecretKeys(Object? value, String path) {
    if (value is Map<Object?, Object?>) {
      value.forEach((k, v) {
        if (shouldRedactField('$k', v)) {
          throw ArgumentError.value(
            '$path.$k',
            'profile',
            'sieht nach einem Secret aus; Secrets gehören in den SecretStore',
          );
        }
        _checkNoSecretKeys(v, '$path.$k');
      });
    } else if (value is List<Object?>) {
      for (var i = 0; i < value.length; i++) {
        _checkNoSecretKeys(value[i], '$path[$i]');
      }
    }
  }
}
