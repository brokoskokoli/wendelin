import 'dart:io';

import 'package:meta/meta.dart';

/// Files of an unpacked Piper/VITS or Kokoro voice (sherpa-onnx export).
@immutable
final class PiperVoiceFiles {
  /// Creates the paths.
  const PiperVoiceFiles({
    required this.model,
    required this.tokens,
    required this.dataDir,
    this.voicesBin,
    this.dictDir,
    this.lexicon,
  });

  /// Finds the voice in [directory]: the archive's top folder with one
  /// `*.onnx`, `tokens.txt` and `espeak-ng-data/` (Kokoro: also
  /// `voices.bin`, and `dict/` and `lexicon-*-en.txt` if present).
  /// Returns `null` if something is missing.
  ///
  /// [kokoro] (from the catalog entry, [TtsSynth.kokoro]) says what the
  /// model is: a Kokoro model without `voices.bin` is not usable (`null`,
  /// never loaded as Piper), a Piper voice ignores a stray `voices.bin`.
  /// `null` = decide by the files.
  static PiperVoiceFiles? find(Directory directory, {bool? kokoro}) {
    if (!directory.existsSync()) return null;
    final dirs = [directory, ...directory.listSync().whereType<Directory>()];
    for (final d in dirs) {
      final onnx = d
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.onnx'))
          .toList();
      final tokens = File('${d.path}/tokens.txt');
      final data = Directory('${d.path}/espeak-ng-data');
      if (onnx.length == 1 && tokens.existsSync() && data.existsSync()) {
        final hasVoices = File('${d.path}/voices.bin').existsSync();
        if (kokoro ?? false) {
          if (!hasVoices) continue;
        }
        return PiperVoiceFiles(
          model: onnx.single.path,
          tokens: tokens.path,
          dataDir: data.path,
          voicesBin: hasVoices && kokoro != false
              ? '${d.path}/voices.bin'
              : null,
          dictDir: Directory('${d.path}/dict').existsSync()
              ? '${d.path}/dict'
              : null,
          lexicon: _englishLexicons(d),
        );
      }
    }
    return null;
  }

  /// All `lexicon-*-en.txt` of [d], comma-separated (as sherpa expects), or
  /// `null` if there is none.
  static String? _englishLexicons(Directory d) {
    final names =
        d
            .listSync()
            .whereType<File>()
            .map((f) => f.path)
            .where((p) => RegExp(r'/lexicon-[^/]*-en\.txt$').hasMatch(p))
            .toList()
          ..sort();
    return names.isEmpty ? null : names.join(',');
  }

  /// Voice `.onnx`.
  final String model;

  /// `tokens.txt`.
  final String tokens;

  /// `espeak-ng-data` directory.
  final String dataDir;

  /// Kokoro `voices.bin`; `null` = a Piper voice.
  final String? voicesBin;

  /// Kokoro `dict/` directory (Chinese segmentation), if present.
  final String? dictDir;

  /// Kokoro English lexicon, if present (used for English only).
  final String? lexicon;
}
