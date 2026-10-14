import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/battery_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(batteryChannelName);

  group('BatteryStatus.fromChannel', () {
    test('liest alle Felder', () {
      final s = BatteryStatus.fromChannel({
        'ignoring': false,
        'bucket': 'working_set',
        'vendor': 'xiaomi',
        'vendorSettings': true,
      });
      expect(s.ignoringOptimizations, isFalse);
      expect(s.bucket, StandbyBucket.workingSet);
      expect(s.vendor, 'xiaomi');
      expect(s.vendorSettings, isTrue);
      expect(s.hasHints, isTrue);
    });

    test('unbekannt oder fehlend: keine Hinweise', () {
      for (final raw in [null, 'x', <String, Object?>{}]) {
        final s = BatteryStatus.fromChannel(raw);
        expect(s.hasHints, isFalse, reason: '$raw');
      }
      expect(StandbyBucket.parse('quatsch'), isNull);
    });

    test('Bucket: nur rare und restricted begrenzen', () {
      expect(StandbyBucket.rare.limited, isTrue);
      expect(StandbyBucket.restricted.limited, isTrue);
      expect(StandbyBucket.frequent.limited, isFalse);
      expect(StandbyBucket.never.limited, isFalse);
    });
  });

  group('BatteryPlatform (Mock-Kanal statt BatteryChannel.kt)', () {
    late List<String> calls;
    late bool fail;

    setUp(() {
      calls = [];
      fail = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (fail) throw PlatformException(code: 'failed');
        return switch (call.method) {
          'status' => {'ignoring': true, 'bucket': 'rare', 'vendor': null},
          _ => true,
        };
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('ruft die Kanal-Methoden auf', () async {
      final p = BatteryPlatform();
      expect((await p.status()).bucket, StandbyBucket.rare);
      expect(await p.requestIgnoreOptimizations(), isTrue);
      expect(await p.openBatterySettings(), isTrue);
      expect(await p.openVendorSettings(), isTrue);
      expect(calls, [
        'status',
        'requestIgnoreOptimizations',
        'openBatterySettings',
        'openVendorSettings',
      ]);
    });

    test('Fehler und fehlendes Plugin: false bzw. kein Hinweis', () async {
      final p = BatteryPlatform();
      fail = true;
      expect(await p.requestIgnoreOptimizations(), isFalse);
      expect((await p.status()).hasHints, isFalse);
      messenger.setMockMethodCallHandler(channel, null);
      expect(await p.openVendorSettings(), isFalse);
    });
  });
}
