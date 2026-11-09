import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/audio_devices_providers.dart';
import 'package:wendelin/platform/voice/audio_devices.dart';
import 'package:wendelin/platform/voice/audio_devices_fake.dart';

const _in = AudioDirection.input;
const _out = AudioDirection.output;
const _mic = AudioDevice(
  key: '15||',
  type: AudioDeviceType.builtinMic,
  name: 'Pixel',
);
const _buds = AudioDevice(
  key: '7|Buds|aabbccdd',
  type: AudioDeviceType.bluetoothSco,
  name: 'Buds',
);

ProviderContainer _container(FakeAudioDevicesPort port) {
  final c = ProviderContainer(
    overrides: [audioDevicesPortProvider.overrideWithValue(port)],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> _settle(ProviderContainer c) async {
  c.listen(audioDevicesProvider, (_, _) {});
  await c.read(audioSelectionProvider.future);
  await c.read(audioDevicesProvider.future);
}

void main() {
  group('resolveAudioChoice', () {
    test('keine Wahl: System, nicht fehlend', () {
      final c = resolveAudioChoice(null, [_mic]);
      expect(c.active, isNull);
      expect(c.selectedMissing, isFalse);
    });

    test('Wahl verbunden: aktiv; fehlend: System und markiert', () {
      expect(resolveAudioChoice(_buds, [_mic, _buds]).active, _buds);
      final missing = resolveAudioChoice(_buds, [_mic]);
      expect(missing.active, isNull);
      expect(missing.selectedMissing, isTrue);
      expect(missing.selected, _buds);
    });

    test('gleicher Schlüssel, anderes Objekt (Wiederverbinden): gewählt', () {
      const again = AudioDevice(
        key: '7|Buds|aabbccdd',
        type: AudioDeviceType.bluetoothSco,
        name: 'Buds 2',
      );
      expect(resolveAudioChoice(_buds, [again]).active, again);
    });

    test('anderer Schlüssel mit gleichem Namen ist ein anderes Gerät', () {
      const other = AudioDevice(
        key: '7|Buds|11223344',
        type: AudioDeviceType.bluetoothSco,
        name: 'Buds',
      );
      expect(resolveAudioChoice(_buds, [other]).active, isNull);
    });
  });

  group('Provider mit Fake', () {
    test('Standard ohne Wahl: System für beide Richtungen', () async {
      final c = _container(
        FakeAudioDevicesPort(list: const AudioDeviceList(input: [_mic])),
      );
      await _settle(c);
      expect(c.read(audioChoiceProvider(_in)).active, isNull);
      expect(c.read(audioChoiceProvider(_out)).selected, isNull);
    });

    test(
      'Wahl übersteht Neustart (zweiter Container, gleicher Speicher)',
      () async {
        final port = FakeAudioDevicesPort(
          list: const AudioDeviceList(input: [_mic, _buds]),
        );
        final first = _container(port);
        await _settle(first);
        await first.read(audioSelectionProvider.notifier).select(_in, _buds);
        expect(first.read(audioChoiceProvider(_in)).active, _buds);

        final second = _container(port);
        await _settle(second);
        expect(second.read(audioChoiceProvider(_in)).active, _buds);
        expect(second.read(audioChoiceProvider(_out)).selected, isNull);
      },
    );

    test('Gerät geht: System; kommt mit gleichem Schlüssel zurück: wieder '
        'gewählt', () async {
      final port = FakeAudioDevicesPort(
        list: const AudioDeviceList(input: [_mic, _buds]),
        selected: const AudioSelection(input: _buds),
      );
      final c = _container(port);
      await _settle(c);
      final seen = <AudioChoice>[];
      c.listen(audioChoiceProvider(_in), (_, v) => seen.add(v));

      port.disconnect(_in, _buds.key);
      await c.read(audioDevicesProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(audioChoiceProvider(_in)).selectedMissing, isTrue);

      port.connect(_in, _buds);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(audioChoiceProvider(_in)).active, _buds);
      expect(seen.map((e) => e.active == null), [true, false]);
    });

    test('zurück auf System löscht die Wahl', () async {
      final port = FakeAudioDevicesPort(
        list: const AudioDeviceList(output: [_buds]),
        selected: const AudioSelection(output: _buds),
      );
      final c = _container(port);
      await _settle(c);
      await c.read(audioSelectionProvider.notifier).select(_out, null);
      expect(c.read(audioChoiceProvider(_out)).selected, isNull);
      expect((await port.selection()).output, isNull);
    });
  });

  group('ChannelAudioDevicesPort', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel(audioDevicesChannelName);
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'devices' => {
            'input': [
              {'key': 'k1', 'type': 'usb', 'name': 'Mic'},
              {'key': '', 'type': 'usb'},
              'kaputt',
            ],
            'output': [
              {'key': 'k2', 'type': 'neu_unbekannt'},
            ],
          },
          'selection' => {
            'input': {'key': 'k1', 'type': 'usb', 'name': 'Mic'},
            'output': null,
          },
          _ => null,
        };
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test(
      'liest Geräte robust: ungültige Einträge weg, unbekannter Typ other',
      () async {
        final list = await ChannelAudioDevicesPort().devices();
        expect(list.input.map((d) => d.key), ['k1']);
        expect(list.output.single.type, AudioDeviceType.other);
        expect(list.output.single.name, '');
      },
    );

    test('liest die Wahl; select sendet Schlüssel, Typ, Name', () async {
      final port = ChannelAudioDevicesPort();
      expect((await port.selection()).input?.key, 'k1');
      expect((await port.selection()).output, isNull);
      await port.select(_out, _buds);
      expect(calls.last.method, 'setSelection');
      expect(calls.last.arguments, {
        'direction': 'output',
        'key': _buds.key,
        'type': 'bluetooth_sco',
        'name': 'Buds',
      });
      await port.select(_in, null);
      expect((calls.last.arguments as Map)['key'], isNull);
    });

    test('devicesChanged liefert die neue Liste', () async {
      final port = ChannelAudioDevicesPort();
      final next = port.changes.first;
      await messenger.handlePlatformMessage(
        audioDevicesChannelName,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('devicesChanged'),
        ),
        (_) {},
      );
      expect((await next).input.single.key, 'k1');
    });

    test('ohne Plattformseite: keine Geräte, System; select wirft', () async {
      messenger.setMockMethodCallHandler(channel, null);
      final port = ChannelAudioDevicesPort();
      expect(await port.devices(), const AudioDeviceList());
      expect((await port.selection()).input, isNull);
      await expectLater(port.select(_in, _mic), throwsA(isA<Exception>()));
    });

    test('Gerät ohne Adresse im Text', () {
      expect(_buds.toString(), isNot(contains('aabb')));
      expect(_buds.toString(), isNot(contains(_buds.key)));
    });
  });
}
