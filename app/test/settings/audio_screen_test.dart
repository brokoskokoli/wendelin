import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/audio_devices_providers.dart';
import 'package:wendelin/platform/voice/audio_devices.dart';
import 'package:wendelin/platform/voice/audio_devices_fake.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/settings/audio_screen.dart';
import 'package:wendelin/ui/settings/settings_screen.dart';

import '../support/test_env.dart';
import 'integrations_screen_test.dart' show settle;
import 'lists_and_web_test.dart' show pumpPage;

const _bt = AudioDevice(
  key: 'k-bt',
  type: AudioDeviceType.bluetoothSco,
  name: 'Kopfhörer X',
);
const _usb = AudioDevice(
  key: 'k-usb',
  type: AudioDeviceType.usb,
  name: 'Box U',
);
const _mic = AudioDevice(
  key: 'k-mic',
  type: AudioDeviceType.builtinMic,
  name: 'Handy-Mikro',
);

/// A port whose store fails (channel error); the rest is the fake.
final class _FailingPort implements AudioDevicesPort {
  _FailingPort(this._fake);

  final FakeAudioDevicesPort _fake;

  @override
  Stream<AudioDeviceList> get changes => _fake.changes;

  @override
  Future<AudioDeviceList> devices() => _fake.devices();

  @override
  Future<AudioSelection> selection() => _fake.selection();

  @override
  Future<void> select(AudioDirection direction, AudioDevice? device) =>
      throw StateError('kaputt');
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  AudioDevicesPort port,
) async {
  if (port is FakeAudioDevicesPort) addTearDown(port.dispose);
  return pumpPage(
    tester,
    TestEnv(extraOverrides: [audioDevicesPortProvider.overrideWithValue(port)]),
    const AudioScreen(),
  );
}

void main() {
  testWidgets('zeigt Geräte mit Name und Typ, nie den Schlüssel', (
    tester,
  ) async {
    final port = FakeAudioDevicesPort(
      list: const AudioDeviceList(input: [_mic, _bt], output: [_usb]),
    );
    await _pump(tester, port);
    expect(find.text('Handy-Mikro'), findsOneWidget);
    expect(find.text('Eingebautes Mikrofon'), findsOneWidget);
    expect(find.text('Kopfhörer X'), findsOneWidget);
    expect(find.text('Bluetooth (Headset)'), findsOneWidget);
    expect(find.text('Box U'), findsOneWidget);
    expect(find.textContaining('k-bt'), findsNothing);
    expect(find.text('Gerade benutzt: System'), findsNWidgets(2));
    expect(find.textContaining('nicht für Musik anderer Apps'), findsOneWidget);
  });

  testWidgets(
    'Auswahl speichert, zeigt „gerade benutzt“; System setzt zurück',
    (tester) async {
      final port = FakeAudioDevicesPort(
        list: const AudioDeviceList(input: [_mic, _bt]),
      );
      final c = await _pump(tester, port);
      await tester.tap(find.text('Kopfhörer X'));
      await settle(tester);
      expect((await port.selection()).input, _bt);
      expect(c.read(audioChoiceProvider(AudioDirection.input)).active, _bt);
      expect(find.text('Gerade benutzt: Kopfhörer X'), findsOneWidget);
      Finder check(String t) => find.descendant(
        of: find.widgetWithText(InkWell, t),
        matching: find.byType(CheckStatusIcon),
      );
      expect(check('Kopfhörer X'), findsOneWidget);
      expect(check('Handy-Mikro'), findsNothing);
      // Output untouched.
      expect((await port.selection()).output, isNull);

      await tester.tap(find.text('System').first);
      await settle(tester);
      expect((await port.selection()).input, isNull);
      expect(find.text('Gerade benutzt: Kopfhörer X'), findsNothing);
    },
  );

  testWidgets(
    'fehlendes Gerät bleibt sichtbar, markiert; Rückkehr aktualisiert',
    (tester) async {
      final port = FakeAudioDevicesPort(
        list: const AudioDeviceList(input: [_mic]),
        selected: const AudioSelection(input: _bt),
      );
      await _pump(tester, port);
      expect(find.text('Kopfhörer X'), findsOneWidget);
      expect(
        find.textContaining('nicht verbunden, System wird benutzt'),
        findsOneWidget,
      );
      expect(find.text('Gerade benutzt: System'), findsNWidgets(2));

      port.connect(AudioDirection.input, _bt);
      await settle(tester);
      expect(find.textContaining('nicht verbunden'), findsNothing);
      expect(find.text('Kopfhörer X'), findsOneWidget);
      expect(find.text('Gerade benutzt: Kopfhörer X'), findsOneWidget);

      port.disconnect(AudioDirection.input, 'k-bt');
      await settle(tester);
      expect(find.textContaining('nicht verbunden'), findsOneWidget);
    },
  );

  testWidgets('Speicherfehler: Hinweis, Auswahl bleibt unverändert', (
    tester,
  ) async {
    final port = _FailingPort(
      FakeAudioDevicesPort(list: const AudioDeviceList(output: [_usb])),
    );
    final c = await _pump(tester, port);
    await tester.tap(find.text('Box U'));
    await settle(tester);
    expect(
      find.text('Die Wahl konnte nicht gespeichert werden.'),
      findsOneWidget,
    );
    expect(c.read(audioChoiceProvider(AudioDirection.output)).selected, isNull);
    expect(find.text('Gerade benutzt: System'), findsNWidgets(2));
  });

  testWidgets('Einstellungsliste: Audio auf Android, Tippen öffnet die Seite', (
    tester,
  ) async {
    await pumpPage(tester, TestEnv(), const SettingsScreen());
    expect(find.text('Audio'), findsOneWidget);
    await tester.tap(find.text('Audio'));
    await settle(tester);
    expect(find.byType(AudioScreen), findsOneWidget);
  });

  testWidgets('Einstellungsliste: auf iOS kein Audio-Eintrag', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpPage(tester, TestEnv(), const SettingsScreen());
      expect(find.text('Audio'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
