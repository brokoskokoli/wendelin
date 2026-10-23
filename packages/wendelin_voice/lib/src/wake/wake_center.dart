import 'dart:convert';
import 'dart:typed_data';

import 'wake_center_mean.g.dart';

export 'wake_center_mean.g.dart' show wakeCenterFeatureVersion, wakeCenterId;

/// Fixed mean of the wake embedding windows (1 536 values, WP134), decoded
/// once from the generated constant. Template and live window are centered
/// with it before the cosine (`bestSimilarity(mean: …)`).
final Float32List wakeCenterMean = _decode();

Float32List _decode() {
  final bytes = base64Decode(wakeCenterMeanBase64);
  if (bytes.length != 1536 * 4) {
    throw StateError('Mittel hat ${bytes.length ~/ 4} statt 1536 Werte');
  }
  final copy = Uint8List.fromList(bytes);
  return copy.buffer.asFloat32List(0, 1536);
}
