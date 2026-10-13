import 'dart:convert';
import 'dart:io';

import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/platform/voice/sherpa_runtime.dart';

/// Directory with downloaded models for the desktop FFI tests
/// (`WENDELIN_MODELS=<dir>`, one folder per catalog id); `null` = skip.
final String? modelsDir = Platform.environment['WENDELIN_MODELS'];

/// Skip reason for FFI tests without models (or not on macOS).
String? get ffiSkip {
  if (!Platform.isMacOS) return 'nur auf macOS (sherpa_onnx_macos)';
  if (modelsDir == null) return 'WENDELIN_MODELS nicht gesetzt';
  return null;
}

/// Points sherpa-onnx at `sherpa_onnx_macos` from the workspace package
/// config (`flutter test` cannot resolve it on its own).
void useDesktopSherpa() {
  final config = File('../.dart_tool/package_config.json');
  final packages =
      (jsonDecode(config.readAsStringSync())
              as Map<String, Object?>)['packages']
          as List<Object?>;
  final macos = packages.cast<Map<String, Object?>>().firstWhere(
    (p) => p['name'] == 'sherpa_onnx_macos',
  );
  sherpaLibraryDir =
      '${Uri.parse(macos['rootUri']! as String).toFilePath()}/macos';
}

/// Fixture WAV `test/fixtures/stt/<id>.wav`.
Wav fixture(String id) => Wav.read('test/fixtures/stt/$id.wav');
