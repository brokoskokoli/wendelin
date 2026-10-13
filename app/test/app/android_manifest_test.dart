import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Checks the Android configuration that protects local data and keeps the
/// app free of unneeded permissions (concept: Sicherheit, K7).
void main() {
  const res = 'android/app/src/main/res/xml';
  final manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();

  test('kein Backup: allowBackup aus, Regeln für alle Wege gesetzt', () {
    expect(manifest, contains('android:allowBackup="false"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
  });

  const domains = ['root', 'file', 'database', 'sharedpref', 'external'];

  Iterable<String> excluded(String xml) =>
      RegExp(r'<exclude domain="(\w+)" path="\." />')
          .allMatches(xml)
          .map((m) => m[1]!);

  test('Datenextraktion: Cloud-Backup und Geräteumzug schließen alles aus', () {
    final xml = File('$res/data_extraction_rules.xml').readAsStringSync();
    for (final section in ['cloud-backup', 'device-transfer']) {
      final body = RegExp(
        '<$section>(.*?)</$section>',
        dotAll: true,
      ).firstMatch(xml)?[1];
      expect(body, isNotNull, reason: section);
      expect(excluded(body!).toSet(), containsAll(domains), reason: section);
      expect(body, isNot(contains('<include')), reason: section);
    }
  });

  test('Auto Backup (bis Android 11) schließt alles aus', () {
    final xml = File('$res/backup_rules.xml').readAsStringSync();
    expect(excluded(xml).toSet(), containsAll(domains));
    expect(xml, isNot(contains('<include')));
  });

  test('nur die nötigen Berechtigungen', () {
    final permissions = RegExp(r'<uses-permission android:name="([^"]+)"')
        .allMatches(manifest)
        .map((m) => m[1])
        .toSet();
    expect(permissions, {
      'android.permission.INTERNET',
      'android.permission.READ_CALENDAR',
      'android.permission.WRITE_CALENDAR',
      'com.android.alarm.permission.SET_ALARM',
    });
  });
}
