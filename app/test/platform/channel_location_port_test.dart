import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/channel_location_port.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(locationChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  Object? Function(MethodCall call) answer = (_) => null;

  setUp(() {
    calls.clear();
    answer = (_) => null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final r = answer(call);
      if (r is PlatformException) throw r;
      return r;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<PortException> failure(Future<Object?> Function() run) async {
    try {
      await run();
    } on PortException catch (e) {
      return e;
    }
    fail('keine PortException');
  }

  test('Berechtigung: fragen und anfragen', () async {
    answer = (c) => c.method == 'hasPermission' ? false : true;
    const port = ChannelLocationPort();
    expect(await port.hasPermission(), isFalse);
    expect(await port.requestPermission(), isTrue);
    expect(calls.map((c) => c.method), ['hasPermission', 'requestPermission']);
  });

  test('current liest Koordinaten, Genauigkeit und Ortsname', () async {
    answer = (_) => {
      'latitude': 53.5,
      'longitude': 10,
      'accuracyM': 12.5,
      'place': 'Altstadt, Hamburg',
    };
    final fix = await const ChannelLocationPort().current();
    expect(fix.latitude, 53.5);
    expect(fix.longitude, 10.0);
    expect(fix.accuracyMeters, 12.5);
    expect(fix.placeName, 'Altstadt, Hamburg');
  });

  test('current ohne Ortsname und Genauigkeit', () async {
    answer = (_) => {
      'latitude': 1.0,
      'longitude': 2.0,
      'accuracyM': null,
      'place': '',
    };
    final fix = await const ChannelLocationPort().current();
    expect(fix.accuracyMeters, isNull);
    expect(fix.placeName, isNull);
  });

  test(
    'current mit kaputter Antwort: unavailable ohne Werte im Text',
    () async {
      answer = (_) => {'latitude': 'x'};
      final e = await failure(() => const ChannelLocationPort().current());
      expect(e.kind, PortErrorKind.unavailable);
    },
  );

  test(
    'Fehlercodes werden zu deutschen PortExceptions ohne Koordinaten',
    () async {
      const port = ChannelLocationPort();
      for (final (code, kind) in [
        ('permissionDenied', PortErrorKind.permissionDenied),
        ('unavailable', PortErrorKind.unavailable),
        ('failed', PortErrorKind.failed),
      ]) {
        answer = (_) => PlatformException(code: code, message: '53.55,9.99');
        final e = await failure(port.current);
        expect(e.kind, kind, reason: code);
        expect(e.message, isNot(contains('53.55')));
      }
    },
  );

  test('fehlendes Plugin: unsupported', () async {
    messenger.setMockMethodCallHandler(channel, null);
    final e = await failure(() => const ChannelLocationPort().current());
    expect(e.kind, PortErrorKind.unsupported);
  });

  test('Launcher schickt URI und Paket, notFound wird übersetzt', () async {
    const launcher = ChannelMapsLauncherPort();
    await launcher.launch(MapsIntents.navigate('Hafen', googleMaps: true));
    expect(calls.single.method, 'launch');
    expect(calls.single.arguments, {
      'uri': 'google.navigation:q=Hafen&mode=d',
      'package': googleMapsPackage,
    });
    calls.clear();
    await launcher.launch(MapsIntents.search('Bar', googleMaps: false));
    expect(calls.single.arguments, {'uri': 'geo:0,0?q=Bar'});
    answer = (_) => PlatformException(code: 'notFound');
    final e = await failure(
      () => launcher.launch(MapsIntents.search('Bar', googleMaps: false)),
    );
    expect(e.kind, PortErrorKind.notFound);
  });
}
