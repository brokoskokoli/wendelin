import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/golden_tolerance.dart';

/// PNG of a white 100×100 image with [dark] black pixels in the first rows.
Future<Uint8List> _png(int dark) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawRect(
      const ui.Rect.fromLTWH(0, 0, 100, 100),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
  final black = ui.Paint()..color = const ui.Color(0xFF000000);
  for (var i = 0; i < dark; i++) {
    canvas.drawRect(
      ui.Rect.fromLTWH((i % 100).toDouble(), (i ~/ 100).toDouble(), 1, 1),
      black,
    );
  }
  final image = await recorder.endRecording().toImage(100, 100);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  testWidgets('CI-Toleranz: bis 1,0 % und 2000 Pixel ok, darüber Fehler', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('golden_tol');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/g.png').writeAsBytesSync(await _png(0));
      final comparator = TolerantGoldenComparator(
        Uri.file('${dir.path}/x_test.dart'),
        tolerance: ciGoldenTolerance,
        maxPixels: ciGoldenMaxPixels,
      );
      final golden = Uri.parse('g.png');

      expect(await comparator.compare(await _png(0), golden), isTrue);
      expect(
        await comparator.compare(await _png(56), golden),
        isTrue,
        reason: '0,56 % wie auf dem macOS-Runner',
      );
      expect(
        await comparator.compare(await _png(89), golden),
        isTrue,
        reason: '0,89 % wie kleine Textkarten auf dem macOS-Runner',
      );
      await expectLater(
        comparator.compare(await _png(110), golden),
        throwsA(isA<FlutterError>()),
        reason: '1,1 % liegt über dem Anteil',
      );
      final strict = TolerantGoldenComparator(
        Uri.file('${dir.path}/x_test.dart'),
        tolerance: ciGoldenTolerance,
        maxPixels: 50,
      );
      await expectLater(
        strict.compare(await _png(56), golden),
        throwsA(isA<FlutterError>()),
        reason: 'über der absoluten Pixelgrenze',
      );
    });
  });

  test('pngPixelCount liest die Größe aus dem PNG', () async {
    expect(pngPixelCount(await _png(0)), 10000);
  });

  test('nur mit CI=true aktiv', () {
    final before = goldenFileComparator;
    addTearDown(() => goldenFileComparator = before);
    goldenFileComparator = LocalFileComparator(Uri.file('/tmp/a_test.dart'));
    useCiGoldenTolerance(environment: const {});
    expect(goldenFileComparator, isNot(isA<TolerantGoldenComparator>()));
    useCiGoldenTolerance(environment: const {'CI': 'true'});
    expect(goldenFileComparator, isA<TolerantGoldenComparator>());
    expect(
      (goldenFileComparator as LocalFileComparator).basedir,
      Uri.file('/tmp/'),
    );
  });
}
