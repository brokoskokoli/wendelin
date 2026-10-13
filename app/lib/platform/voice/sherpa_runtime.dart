import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

bool _ready = false;

/// Directory of the native library for hosts where sherpa-onnx cannot find
/// it itself (`flutter test` on macOS); set before the first use. Spawned
/// isolates inherit nothing, so the Whisper/TTS isolates get it passed.
String? sherpaLibraryDir;

/// Loads the sherpa-onnx native library once for the current isolate.
///
/// Every isolate has its own FFI state, so the Whisper and TTS isolates
/// call this again. On Android the library comes from the
/// `sherpa_onnx_android_*` plugins, on macOS (tests, measurement tools)
/// from `sherpa_onnx_macos` in the pub cache.
void ensureSherpaBindings([String? libraryDir]) {
  if (_ready) return;
  so.initBindings(libraryDir ?? sherpaLibraryDir);
  _ready = true;
}
