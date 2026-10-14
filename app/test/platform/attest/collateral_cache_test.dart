import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/attest/attestation_port.dart';
import 'package:wendelin/platform/attest/collateral_cache.dart';

void main() {
  late Directory dir;
  var now = DateTime.utc(2026, 10, 14);
  late CollateralCache cache;
  final c = QuoteCollateral(
    Uint8List.fromList(utf8.encode('{"x":1}')),
    validUntil: DateTime.utc(2026, 11, 12, 22, 38, 12),
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('attest-cache');
    now = DateTime.utc(2026, 10, 14);
    cache = CollateralCache(dir: Directory('${dir.path}/sub'), now: () => now);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('speichert und liest bis nextUpdate, danach nicht mehr', () {
    expect(cache.read('tdx-A-processor'), isNull);
    cache.write('tdx-A-processor', c);
    final r = cache.read('tdx-A-processor');
    expect(utf8.decode(r!.json), '{"x":1}');
    expect(r.validUntil, c.validUntil);
    now = c.validUntil!.subtract(const Duration(seconds: 1));
    expect(cache.read('tdx-A-processor'), isNotNull);
    now = c.validUntil!;
    expect(cache.read('tdx-A-processor'), isNull);
  });

  test('Schlüssel sind getrennt und Sonderzeichen bleiben im Ordner', () {
    cache.write('a', c);
    cache.write('../b', c);
    expect(cache.read('a'), isNotNull);
    expect(cache.read('../b'), isNotNull);
    expect(Directory('${dir.path}/sub').listSync().length, 2);
  });

  test('beschädigte Datei ergibt null statt Fehler', () {
    cache.write('k', c);
    File('${dir.path}/sub/collateral-k.json').writeAsStringSync('{kaputt');
    expect(cache.read('k'), isNull);
  });
}
