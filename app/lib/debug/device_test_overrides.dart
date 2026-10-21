import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:path_provider/path_provider.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/flashlight.dart' show TorchPort;

import '../di/provider_config.dart';
import '../di/providers.dart';
import '../di/voice_providers.dart';
import '../platform/platform_ports.dart';
import '../platform/voice/wav_audio_input.dart';
import '../voice/voice_log.dart';

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
///   ([WavAudioInput]); a list plays one file per recording (command, then
///   the spoken answer to a confirmation),
/// - `waitForBargeListen`: indices of the `audio` recordings that start
///   only after the barge-in listener runs (`barge-listen on=true`, WP120):
///   the WAV does not run by the wall clock under load,
/// - `torch`: `"file"` = the flashlight port writes `on`/`off` into
///   `files/e2e/torch-state` instead of using the LED (WP53, an emulator
///   has none, and the test engine cannot see the overlay engine's port),
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
  // Invalid specs fail here, not only when the provider is first read.
  if (audio is List<Object?>) _wavs(dir, audio);
  final turns = raw is List<Object?> ? _turns(raw) : null;
  return [
    if (audio is String) audioInputProvider.overrideWithValue(_wav(dir, audio)),
    if (audio is List<Object?>)
      audioInputProvider.overrideWith(
        (ref) => _wavs(dir, audio, gate: _bargeGate(ref, spec)),
      ),
    if (spec['torch'] == 'file')
      platformPortsProvider.overrideWith((ref) {
        final demo = ref.watch(demoPortsProvider);
        return PlatformPorts(
          calendar: demo.calendar,
          clipboard: demo.clipboard,
          alarms: demo.alarms,
          memory: demo.memory,
          apps: demo.apps,
          torch: FileTorchPort('$dir/torch-state'),
          lists: demo.lists,
          obsidian: demo.obsidian,
        );
      }),
    if (turns != null)
      storedProviderConfigProvider.overrideWith(
        (ref) async => deviceTestProviderConfig(FakeLlmProvider(turns)),
      ),
  ];
}

String _wavPath(String dir, Object? name) {
  if (name is! String ||
      name.isEmpty ||
      name.contains('/') ||
      name.contains(r'\')) {
    throw FormatException('audio: nur ein Dateiname, nicht „$name“');
  }
  return '$dir/$name';
}

WavAudioInput _wav(String dir, String name) =>
    WavAudioInput.file(_wavPath(dir, name));

/// [TorchPort] of the device tests: the state lives in a file.
final class FileTorchPort implements TorchPort {
  /// Creates the port on [path].
  FileTorchPort(this.path);

  /// File holding `on` or `off`.
  final String path;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> state() async {
    final f = File(path);
    return f.existsSync() && f.readAsStringSync().trim() == 'on';
  }

  @override
  Future<void> set(bool on) async =>
      File(path).writeAsStringSync(on ? 'on' : 'off');
}

/// One WAV per recording (command, then the spoken answer, WP30).
WavAudioInput _wavs(
  String dir,
  List<Object?> names, {
  Future<void> Function(int index)? gate,
}) {
  if (names.isEmpty) throw const FormatException('audio: leere Liste');
  return WavAudioInput.files([
    for (final n in names) _wavPath(dir, n),
  ], gate: gate);
}

/// Gate for `waitForBargeListen` (null without it): the listed recordings
/// wait until the barge-in listener runs, at most [_bargeWait].
Future<void> Function(int)? _bargeGate(Ref ref, Map<String, Object?> spec) {
  final raw = spec['waitForBargeListen'];
  if (raw is! List<Object?>) return null;
  final gated = {for (final i in raw) ?(i is int ? i : null)};
  var on = false;
  final waiting = <Completer<void>>[];
  ref.listen(bargeListeningProvider, (_, v) {
    on = v;
    if (!v) return;
    for (final w in waiting) {
      if (!w.isCompleted) w.complete();
    }
    waiting.clear();
  }, fireImmediately: true);
  return (index) {
    if (!gated.contains(index) || on) return Future.value();
    final w = Completer<void>();
    waiting.add(w);
    return w.future.timeout(
      _bargeWait,
      onTimeout: () => voiceLog('e2e-gate', {'timeout': true}),
    );
  };
}

const _bargeWait = Duration(seconds: 30);

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
