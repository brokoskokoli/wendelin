import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_requirements.dart';
import 'package:wendelin/di/integration_specs.dart';

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
      'android.permission.ACCESS_NETWORK_STATE',
      'android.permission.READ_CALENDAR',
      'android.permission.WRITE_CALENDAR',
      'com.android.alarm.permission.SET_ALARM',
      'android.permission.POST_NOTIFICATIONS',
      'android.permission.RECORD_AUDIO',
      'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
    });
  });

  test(
    'System-TTS-Engines sind sichtbar (Paket-Sichtbarkeit ab Android 11)',
    () {
      expect(
        manifest,
        contains('<action android:name="android.intent.action.TTS_SERVICE"/>'),
      );
    },
  );

  group('App-Erkennung (WP25)', () {
    final queries = RegExp(
      '<queries>(.*?)</queries>',
      dotAll: true,
    ).firstMatch(manifest)![1]!;
    final declared = RegExp(r'<package android:name="([^"]+)"/>')
        .allMatches(queries)
        .map((m) => m[1])
        .toSet();

    // Hersteller-Einstellungsseiten (WP56, BatteryVendors.kt).
    const vendorPackages = {
      'com.miui.securitycenter',
      'com.miui.powerkeeper',
      'com.samsung.android.lool',
      'com.oneplus.security',
      'com.huawei.systemmanager',
    };

    test('jede bekannte App steht in <queries>, nichts darüber hinaus', () {
      expect(declared, {
        for (final a in KnownApps.all) a.androidPackage,
        ...vendorPackages,
      });
    });

    test('jede App-Anforderung einer Integration ist eine bekannte App', () {
      for (final spec in builtInIntegrationSpecs) {
        final app = spec.requiredApp;
        if (app != null) {
          expect(declared, contains(app.androidPackage), reason: spec.id);
        }
      }
    });

    test('kein QUERY_ALL_PACKAGES, Store-Links ohne Play Store (K7)', () {
      expect(
        manifest,
        isNot(contains('android.permission.QUERY_ALL_PACKAGES')),
      );
      for (final app in KnownApps.all) {
        expect(app.storeUrl, startsWith('https://'));
        expect(app.storeUrl, isNot(contains('play.google.com')));
        expect(app.storeUrl, isNot(startsWith('market:')));
      }
    });

    test('Kanal ist in beiden Engines registriert', () {
      const kotlin = 'android/app/src/main/kotlin/app/wendelin';
      expect(
        File('$kotlin/WendelinActivity.kt').readAsStringSync(),
        contains('AppsChannel(this, messenger)'),
      );
      expect(
        File('$kotlin/AppsChannel.kt').readAsStringSync(),
        contains('"app.wendelin/apps"'),
      );
    });
  });

  group('Standard-Assistent (WP18)', () {
    /// The element declaring `.name`, up to its end (self-closing or
    /// with children).
    String block(String name) {
      final at = manifest.indexOf('android:name=".$name"');
      expect(at, isNonNegative, reason: name);
      final start = manifest.lastIndexOf('<', at);
      final tag = RegExp(r'<(\w+)').firstMatch(manifest.substring(start))![1]!;
      final nextOpen = manifest.indexOf('<', at);
      final selfClose = manifest.indexOf('/>', at);
      final end = selfClose >= 0 && (nextOpen < 0 || selfClose < nextOpen)
          ? selfClose + 2
          : manifest.indexOf('</$tag>', at) + tag.length + 3;
      return manifest.substring(start, end);
    }

    test('VoiceInteractionService nur für das System, mit Metadaten', () {
      final service = block('WendelinVoiceInteractionService');
      expect(
        service,
        contains(
          'android:permission="android.permission.BIND_VOICE_INTERACTION"',
        ),
      );
      expect(
        service,
        contains('android.service.voice.VoiceInteractionService'),
      );
      expect(service, contains('android:name="android.voice_interaction"'));
      expect(
        service,
        contains('android:resource="@xml/voice_interaction_service"'),
      );
    });

    test('Session-Service ebenfalls nur für das System', () {
      expect(
        block('WendelinVoiceSessionService'),
        contains(
          'android:permission="android.permission.BIND_VOICE_INTERACTION"',
        ),
      );
    });

    test('Metadaten: Session, Erkenner, Assist', () {
      final xml = File('$res/voice_interaction_service.xml').readAsStringSync();
      expect(
        xml,
        contains(
          'android:sessionService="app.wendelin.WendelinVoiceSessionService"',
        ),
      );
      expect(
        xml,
        contains(
          'android:recognitionService="app.wendelin.WendelinRecognitionService"',
        ),
      );
      expect(xml, contains('android:supportsAssist="true"'));
      expect(
        block('WendelinRecognitionService'),
        contains('android.speech.RecognitionService'),
      );
    });

    test('Overlay-Activity: nicht exportiert, transparent, ohne Verlauf', () {
      final activity = block('AssistantActivity');
      expect(activity, contains('android:exported="false"'));
      expect(activity, contains('android:theme="@style/AssistantTheme"'));
      expect(activity, contains('android:excludeFromRecents="true"'));
      final styles = File('android/app/src/main/res/values/styles.xml')
          .readAsStringSync();
      expect(styles, contains('<style name="AssistantTheme"'));
      expect(
        styles,
        contains('<item name="android:windowIsTranslucent">true</item>'),
      );
    });

    test(
      'Erkennungsdienst standardmäßig aus, nur mit Assistenten-Rolle an',
      () {
        expect(
          block('WendelinRecognitionService'),
          contains('android:enabled="false"'),
        );
        const kotlin = 'android/app/src/main/kotlin/app/wendelin';
        final service = File('$kotlin/WendelinVoiceInteractionService.kt')
            .readAsStringSync();
        expect(
          service,
          contains('RecognizerSwitch.sync(this, holdsRole = true)'),
        );
        final activity = File('$kotlin/WendelinActivity.kt').readAsStringSync();
        expect(activity, contains('RecognizerSwitch.sync(this)'));
      },
    );

    test('Erkennungsdienst (WP20): Metadaten, Rolle und Einstellung', () {
      final service = block('WendelinRecognitionService');
      expect(service, contains('android:name="android.speech"'));
      expect(service, contains('android:resource="@xml/recognition_service"'));
      expect(
        File('$res/recognition_service.xml').readAsStringSync(),
        contains('<recognition-service'),
      );
      const kotlin = 'android/app/src/main/kotlin/app/wendelin';
      final switcher = File('$kotlin/RecognizerSwitch.kt').readAsStringSync();
      // Enabled only with the role and while offered (default on).
      expect(switcher, contains('holdsRole && isOffered(context)'));
      expect(switcher, contains('getBoolean(KEY_OFFERED, true)'));
      final recognizer = File('$kotlin/WendelinRecognitionService.kt')
          .readAsStringSync();
      // Checked again per request (role changes are not observable).
      expect(recognizer, contains('RecognizerSwitch.isActive(this)'));
      // Test audio only in debuggable builds.
      expect(
        File('$kotlin/RecognizerAudio.kt').readAsStringSync(),
        contains('ApplicationInfo.FLAG_DEBUGGABLE'),
      );
    });

    test('Overlay immer mit FLAG_SECURE', () {
      final overlay = File(
        'android/app/src/main/kotlin/app/wendelin/AssistantActivity.kt',
      ).readAsStringSync();
      expect(
        overlay,
        contains('window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)'),
      );
    });

    test('keine neuen Laufzeit-Berechtigungen für den Assistenten', () {
      expect(
        manifest,
        isNot(
          contains(
            'uses-permission android:name="android.permission.BIND_VOICE_INTERACTION"',
          ),
        ),
      );
    });
  });
}
