import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/restricted_settings_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(restrictedSettingsChannelName);

  group('RestrictedSettings', () {
    test('mayBeRestricted: nur bei Datei-Quelle', () {
      for (final s in InstallSource.values) {
        expect(
          RestrictedSettings(installSource: s).mayBeRestricted,
          s == InstallSource.file,
          reason: '$s',
        );
      }
    });

    test('fromChannel liest sdk und Quelle, ignoriert alte opMode-Werte', () {
      final s = RestrictedSettings.fromChannel({
        'sdk': 35,
        'opMode': 'allowed',
        'installSource': 'file',
      });
      expect(s.sdk, 35);
      expect(s.installSource, InstallSource.file);
      expect(s.mayBeRestricted, isTrue);
    });

    test('fehlend oder kaputt: unbekannt, kein Fehlalarm', () {
      for (final raw in [
        null,
        'x',
        <String, Object?>{},
        {'sdk': 'x', 'installSource': null},
        {'installSource': 'quatsch'},
      ]) {
        final s = RestrictedSettings.fromChannel(raw);
        expect(s.installSource, InstallSource.unknown, reason: '$raw');
        expect(s.sdk, isNull, reason: '$raw');
        expect(s.mayBeRestricted, isFalse, reason: '$raw');
      }
    });

    test('Namen der Kotlin-Seite', () {
      expect(InstallSource.parse('session'), InstallSource.session);
      expect(InstallSource.parse('file'), InstallSource.file);
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
          'restrictedSettings' => {'sdk': 35, 'installSource': 'file'},
          _ => true,
        };
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('ruft die Kanal-Methoden auf', () async {
      final p = RestrictedSettingsPlatform();
      expect((await p.state()).mayBeRestricted, isTrue);
      expect(await p.openAppInfo(), isTrue);
      expect(calls, ['restrictedSettings', 'openAppInfo']);
    });

    test(
      'Fehler und fehlendes Plugin: nicht eingeschränkt, Info false',
      () async {
        final p = RestrictedSettingsPlatform();
        fail = true;
        expect((await p.state()).mayBeRestricted, isFalse);
        expect(await p.openAppInfo(), isFalse);
        messenger.setMockMethodCallHandler(channel, null);
        expect((await p.state()).mayBeRestricted, isFalse);
        expect(await p.openAppInfo(), isFalse);
      },
    );
  });
}
