import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/attest/collateral_cache.dart';
import 'package:wendelin/platform/attest/file_kds_cache.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

void main() {
  late Directory dir;
  var now = DateTime.utc(2026, 10, 19);
  late FileKdsCache cache;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kds');
    cache = FileKdsCache(CollateralCache(dir: dir, now: () => now));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('Rundlauf über einen neuen Cache auf demselben Ordner', () async {
    await cache.save(
      'ab?x=1&y=2',
      KdsEntry(
        vcek: Uint8List.fromList([1, 2, 3]),
        chain: 'PEM',
        product: 'Genoa',
      ),
    );
    final again = FileKdsCache(CollateralCache(dir: dir, now: () => now));
    final e = (await again.load('ab?x=1&y=2'))!;
    expect(e.vcek, [1, 2, 3]);
    expect((e.chain, e.product), ('PEM', 'Genoa'));
    expect(await again.load('anderer'), isNull);
  });

  test('abgelaufene und unlesbare Einträge sind Fehlschläge', () async {
    await cache.save(
      'k',
      KdsEntry(vcek: Uint8List(1), chain: 'c', product: 'p'),
    );
    now = now.add(const Duration(days: 8));
    expect(await cache.load('k'), isNull);
    now = DateTime.utc(2026, 10, 19);
    for (final f in dir.listSync().whereType<File>()) {
      f.writeAsStringSync('kaputt');
    }
    expect(await cache.load('k'), isNull);
  });
}
