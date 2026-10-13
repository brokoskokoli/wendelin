import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:path_provider/path_provider.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../di/provider_config.dart';
import '../di/providers.dart';
import '../di/voice_providers.dart';
import '../platform/voice/wav_audio_input.dart';

/// Name of the folder in the app data (`files/e2e/`) the device tests fill.
const deviceTestFolder = 'e2e';

/// Debug builds only (WP19): overrides of the assistant overlay for device
/// tests. The overlay runs in its own Flutter engine (`assistantMain`), so
/// a device test cannot override its providers; it writes
/// `files/e2e/overlay.json` into the app data instead (`run-as`, only
/// possible for debuggable builds):
///
/// ```json
/// {"audio": "de-05.wav",
///  "turns": [{"tool": "obsidian__append_daily_note",
///             "arguments": {"text": "Zahnarzt angerufen"}},
///            {"text": "Steht in deiner Tagesnotiz."}]}
/// ```
///
/// - `audio`: WAV (16 kHz mono) in `files/e2e/` instead of the microphone
///   ([WavAudioInput]),
/// - `turns`: a scripted provider (`FakeLlmProvider`) instead of the stored
///   profiles: a tool call or a text answer per turn.
///
/// Returns nothing in release builds, without the file or for an invalid
/// one (logged).
Future<List<Override>> deviceTestOverrides({Directory? base}) async {
  if (!kDebugMode) return const [];
  final dir = Directory(
    '${(base ?? await getApplicationSupportDirectory()).path}/'
    '$deviceTestFolder',
  );
  final file = File('${dir.path}/overlay.json');
  if (!file.existsSync()) return const [];
  try {
    return parseDeviceTestOverrides(file.readAsStringSync(), dir.path);
  } on FormatException catch (e) {
    debugPrint('Gerätetest: ${file.path} ungültig: $e');
    return const [];
  }
}

/// The overrides described by [json]; WAV names are relative to [dir].
@visibleForTesting
List<Override> parseDeviceTestOverrides(String json, String dir) {
  final spec = jsonDecode(json);
  if (spec is! Map<String, Object?>) {
    throw const FormatException('Objekt erwartet');
  }
  final audio = spec['audio'];
  final raw = spec['turns'];
  final turns = raw is List<Object?> ? _turns(raw) : null;
  return [
    if (audio is String) audioInputProvider.overrideWithValue(_wav(dir, audio)),
    if (turns != null)
      storedProviderConfigProvider.overrideWith(
        (ref) async => deviceTestProviderConfig(FakeLlmProvider(turns)),
      ),
  ];
}

WavAudioInput _wav(String dir, String name) {
  if (name.isEmpty || name.contains('/') || name.contains(r'\')) {
    throw FormatException('audio: nur ein Dateiname, nicht „$name“');
  }
  return WavAudioInput.file('$dir/$name');
}

List<ScriptedTurn> _turns(List<Object?> raw) => [
  for (final (i, t) in raw.indexed)
    switch (t) {
      {'tool': final String name, 'arguments': final Object? args} =>
        ScriptedTurn.toolCalls([
          ToolCallBlock(
            id: 'e2e-$i',
            name: name,
            argumentsJson: jsonEncode(args ?? const <String, Object?>{}),
          ),
        ]),
      {'text': final String text} => ScriptedTurn.text(text),
      _ => throw FormatException('turns[$i]: „tool“ oder „text“ erwartet'),
    },
];

/// Provider configuration of the device tests: [provider] (usually a
/// scripted `FakeLlmProvider`) as a local target, so sensitive
/// integrations stay usable.
ProviderConfig deviceTestProviderConfig(LlmProvider provider) => ProviderConfig(
  primary: ProviderTarget(
    profileId: 'geraetetest',
    modelId: 'skript',
    provider: provider,
    privacy: PrivacyLevel.local,
  ),
  names: const {'geraetetest': 'Skript (Gerätetest)'},
);
