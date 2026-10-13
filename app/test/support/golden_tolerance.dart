import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pixel share up to which a golden still passes on CI (0.6 %).
///
/// The goldens are recorded on a local Mac; the macOS runner of GitHub
/// Actions rasterises anti-aliased edges and glyphs slightly differently
/// (up to 0.56 % and 618 pixels in run 38331145273). Shapes and colours are
/// additionally checked platform-independently (`test/ui/shapes_test.dart`).
const ciGoldenTolerance = 0.006;

/// Absolute limit of differing pixels on CI, so large goldens cannot hide a
/// real change inside the share.
const ciGoldenMaxPixels = 2000;

/// [LocalFileComparator] that accepts differences up to [tolerance] (share
/// of differing pixels, 0..1) and at most [maxPixels] differing pixels.
/// Larger differences fail with the usual failure images.
final class TolerantGoldenComparator extends LocalFileComparator {
  /// Creates the comparator for goldens next to [testFile].
  TolerantGoldenComparator(
    super.testFile, {
    required this.tolerance,
    required this.maxPixels,
  });

  /// Accepted share of differing pixels.
  final double tolerance;

  /// Accepted number of differing pixels.
  final int maxPixels;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    try {
      if (result.passed) return true;
      final pixels = (result.diffPercent * pngPixelCount(imageBytes)).round();
      if (result.diffPercent <= tolerance && pixels <= maxPixels) return true;
      throw FlutterError(await generateFailureOutput(result, golden, basedir));
    } finally {
      result.dispose();
    }
  }
}

/// On CI (`CI=true`) replaces the default comparator with a
/// [TolerantGoldenComparator]; locally goldens stay pixel-exact.
void useCiGoldenTolerance({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final current = goldenFileComparator;
  if (env['CI'] != 'true' || current is! LocalFileComparator) return;
  goldenFileComparator = TolerantGoldenComparator(
    current.basedir.resolve('_.dart'),
    tolerance: ciGoldenTolerance,
    maxPixels: ciGoldenMaxPixels,
  );
}

/// Width × height from the IHDR chunk of a PNG.
int pngPixelCount(Uint8List png) {
  final data = ByteData.sublistView(png);
  return data.getUint32(16) * data.getUint32(20);
}
