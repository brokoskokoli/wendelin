import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Hands an export file to the Android share sheet.
typedef Exporter = Future<void> Function(
  String fileName,
  String mimeType,
  String content,
);

/// Export through `share_plus` (replaceable in tests).
final exporterProvider = Provider<Exporter>(
  (ref) => (fileName, mimeType, content) async {
    await SharePlus.instance.share(
      ShareParams(
        title: fileName,
        files: [
          XFile.fromData(
            utf8.encode(content),
            mimeType: mimeType,
            name: fileName,
          ),
        ],
        fileNameOverrides: [fileName],
      ),
    );
  },
);
