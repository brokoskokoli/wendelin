import 'dart:convert';

import '../model/setting_key.dart';
import '../repositories/repositories.dart';
import 'database.dart';

/// drift implementation of [SettingsRepository].
final class DriftSettingsRepository implements SettingsRepository {
  /// Creates the repository.
  DriftSettingsRepository(this._db);

  final WendelinDatabase _db;

  @override
  Future<T?> get<T extends Object>(SettingKey<T> key) async {
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(key.name))).getSingleOrNull();
    if (row == null) return key.defaultValue;
    return key.decode(jsonDecode(row.valueJson));
  }

  @override
  Future<void> set<T extends Object>(SettingKey<T> key, T value) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(
        SettingRow(key: key.name, valueJson: jsonEncode(key.encode(value))),
      );

  @override
  Future<void> remove(SettingKey<Object> key) =>
      (_db.delete(_db.settings)..where((s) => s.key.equals(key.name))).go();
}
