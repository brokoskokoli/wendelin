import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/restricted_settings_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(restrictedSettingsChannelName);

  group('isRestricted (Regel)', () {
    test('ignored ist Nachweis, egal welche Quelle', () {
      for (final s in InstallSource.values) {
        expect(isRestricted(RestrictedOpMode.ignored, s), isTrue, reason: '$s');
      }
    });

    test('allowed und default: nie eingeschränkt, auch bei Datei-Quelle', () {
      for (final op in [
        RestrictedOpMode.allowed,
        RestrictedOpMode.defaultMode,
      ]) {
        for (final s in InstallSource.values) {
          expect(isRestricted(op, s), isFalse, reason: '$op $s');
        }
      }
    });

    test('unknown: nur bei Datei-Quelle', () {
      expect(
        isRestricted(RestrictedOpMode.unknown, InstallSource.file),
        isTrue,
      );
      expect(
        isRestricted(RestrictedOpMode.unknown, InstallSource.session),
        isFalse,
      );
      expect(
        isRestricted(RestrictedOpMode.unknown, InstallSource.unknown),
        isFalse,
      );
    });
  });

  group('RestrictedSettings.fromChannel', () {
    test('liest alle Felder', () {
      final s = RestrictedSettings.fromChannel({
        'sdk': 35,
        'opMode': 'ignored',
        'installSource': 'file',
      });
      expect(s.sdk, 35);
      expect(s.opMode, RestrictedOpMode.ignored);
      expect(s.installSource, InstallSource.file);
      expect(s.restricted, isTrue);
    });

    test('fehlend oder kaputt: unknown, kein Fehlalarm', () {
      for (final raw in [
        null,
        'x',
        <String, Object?>{},
        {'sdk': 'x', 'opMode': 7, 'installSource': null},
        {'opMode': 'quatsch', 'installSource': 'quatsch'},
      ]) {
        final s = RestrictedSettings.fromChannel(raw);
        expect(s.opMode, RestrictedOpMode.unknown, reason: '$raw');
        expect(s.installSource, InstallSource.unknown, reason: '$raw');
        expect(s.sdk, isNull, reason: '$raw');
        expect(s.restricted, isFalse, reason: '$raw');
      }
    });

    test(
      'Op fehlt, Datei-Quelle bekannt: eingeschränkt (dokumentierte Regel)',
      () {
        final s = RestrictedSettings.fromChannel({'installSource': 'file'});
        expect(s.restricted, isTrue);
      },
    );

    test('Namen der Kotlin-Seite', () {
      expect(RestrictedOpMode.parse('allowed'), RestrictedOpMode.allowed);
      expect(RestrictedOpMode.parse('default'), RestrictedOpMode.defaultMode);
      expect(InstallSource.parse('session'), InstallSource.session);
    });
  });

  group('RestrictedSettingsPlatform (Mock-Kanal statt Kotlin)', () {
    late List<String> calls;
    late bool fail;

    setUp(() {
      calls = [];
      fail = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (fail) throw PlatformException(code: 'failed');
        return switch (call.method) {
          'restrictedSettings' => {
            'sdk': 35,
            'opMode': 'ignored',
            'installSource': 'file',
          },
          _ => true,
        };
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('ruft die Kanal-Methoden auf', () async {
      final p = RestrictedSettingsPlatform();
      expect((await p.state()).restricted, isTrue);
      expect(await p.openAppInfo(), isTrue);
      expect(calls, ['restrictedSettings', 'openAppInfo']);
    });

    test(
      'Fehler und fehlendes Plugin: nicht eingeschränkt, Info false',
      () async {
        final p = RestrictedSettingsPlatform();
        fail = true;
        expect((await p.state()).restricted, isFalse);
        expect(await p.openAppInfo(), isFalse);
        messenger.setMockMethodCallHandler(channel, null);
        expect((await p.state()).restricted, isFalse);
        expect(await p.openAppInfo(), isFalse);
      },
    );
  });
}
