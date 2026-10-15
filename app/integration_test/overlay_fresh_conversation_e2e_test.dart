// Gerätetest WP67: Jeder Assistenten-Aufruf beginnt ein neues Gespräch, und
// das Overlay-Gespräch erscheint nicht im App-Chat.
//
// Das Overlay hört eine WAV (de-02 „Wie wird das Wetter heute in Berlin?“,
// de-06 „Was steht heute Nachmittag in meinem Kalender?“) und antwortet mit
// einem Skript-Provider, der jede Anfrage in files/e2e/requests.log
// mitschreibt. Die erste Antwort enthält „Glocken“; diese Marke darf in der
// zweiten Anfrage nicht auftauchen (ebenso wenig die erste Frage).
//
// Nur mit `WENDELIN_MODELS=<dir> tool/e2e_android.sh
// integration_test/overlay_fresh_conversation_e2e_test.dart`.

import 'dart:convert';
import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/bootstrap/run_app.dart';
import 'package:wendelin/debug/device_test_overrides.dart';
import 'package:wendelin/di/agent_providers.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/main.dart' as app show openAppStorage;
import 'package:wendelin/ui/overlay/assistant_overlay.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'support/e2e.dart';
import 'support/voice_e2e.dart';

const _mark = 'Glocken';

/// Wraps [inner] and appends each request as a JSON line to [log].
final class _RecordingProvider implements LlmProvider {
  _RecordingProvider(this.inner, this.log);
  final FakeLlmProvider inner;
  final String log;

  @override
  ProviderType get type => inner.type;
  @override
  ProviderCapabilities get caps => inner.caps;
  @override
  Future<List<ModelInfo>> listModels() => inner.listModels();
  @override
  Future<HealthCheck> test() => inner.test();
  @override
  Stream<ChatEvent> chat(ChatRequest req, {CancelToken? cancel}) {
    File(log).writeAsStringSync(
      '${jsonEncode({
        'system': req.systemPrompt ?? '',
        'messages': [for (final m in req.messages) '${m.content}'],
      })}\n',
      mode: FileMode.append,
      flush: true,
    );
    return inner.chat(req, cancel: cancel);
  }
}

/// Overlay entry point: like the real one, but the provider records.
@pragma('vm:entry-point')
Future<void> assistantMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final (storage, startup) = await app.openAppStorage();
  final dir = await e2eDirectory();
  final spec = jsonDecode(
    File('${dir.path}/overlay.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final provider = _RecordingProvider(
    FakeLlmProvider([ScriptedTurn.text(spec['reply']! as String)]),
    '${dir.path}/requests.log',
  );
  await runWendelinApp(
    storage,
    startup,
    const AssistantOverlayApp(),
    extra: [
      sessionOriginProvider.overrideWithValue(SessionOrigin.overlay),
      ...parseDeviceTestOverrides(
        jsonEncode({'audio': spec['audio']}),
        dir.path,
      ),
      storedProviderConfigProvider.overrideWith(
        (ref) async => deviceTestProviderConfig(provider),
      ),
    ],
  );
}

Future<void> _runOverlay(
  Directory e2e,
  File log, {
  required String wav,
  required String reply,
  required int expectedRequests,
}) async {
  File('${e2e.path}/overlay.json')
      .writeAsStringSync(jsonEncode({'audio': '$wav.wav', 'reply': reply}));
  await askHost('assist');
  final end = DateTime.now().add(const Duration(seconds: 90));
  while (!log.existsSync() ||
      log.readAsLinesSync().where((l) => l.isNotEmpty).length <
          expectedRequests) {
    if (DateTime.now().isAfter(end)) fail('Overlay sendet keine Anfrage');
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  // Let the answer be stored before closing.
  await Future<void>.delayed(const Duration(seconds: 4));
  await askHost('back');
  await Future<void>.delayed(const Duration(seconds: 2));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Assistent: jeder Aufruf ein neues Gespräch, kein Leck in den App-Chat',
    (tester) async {
      await waitForDeviceFiles();
      final e2e = await e2eDirectory();
      final log = File('${e2e.path}/requests.log');
      void clean() {
        for (final f in ['overlay.json', 'de-02.wav', 'de-06.wav']) {
          final file = File('${e2e.path}/$f');
          if (file.existsSync()) file.deleteSync();
        }
        if (log.existsSync()) log.deleteSync();
      }

      clean();
      addTearDown(clean);

      final setup = WendelinStorage(driftDatabase(name: 'wendelin'));
      await setup.settings.set(AppSettings.onboardingDone, true);
      await setup.settings.set(
        voiceSettingsKey,
        const VoiceSettings(sttModel: 'whisper-base'),
      );
      await setup.close();
      for (final id in ['de-02', 'de-06']) {
        File(await fixtureWav(id)).copySync('${e2e.path}/$id.wav');
      }

      // 1. First call: "Wetter in Berlin"; the scripted answer carries the mark.
      await _runOverlay(
        e2e,
        log,
        wav: 'de-02',
        reply: 'Glocken sind Schlaginstrumente.',
        expectedRequests: 1,
      );
      // 2. Second call: a different question.
      await _runOverlay(
        e2e,
        log,
        wav: 'de-06',
        reply: 'Nichts im Kalender.',
        expectedRequests: 2,
      );
      final requests = [
        for (final l in log.readAsLinesSync().where((l) => l.isNotEmpty))
          jsonDecode(l) as Map<String, Object?>,
      ];
      // ignore: avoid_print
      print('E2E-Anfragen: ${requests.map((r) => r['messages']).toList()}');
      expect(requests, hasLength(2));
      final second = jsonEncode(requests[1]['messages']);
      expect(second, isNot(contains(_mark)), reason: 'Antwort 1 geleckt');
      expect(second, isNot(contains('Berlin')), reason: 'Frage 1 geleckt');
      expect(jsonEncode(requests[0]['messages']), isNot(contains(_mark)));

      // 3. The app starts normally: its chat does not show the overlay talk.
      final (storage, startup) = await app.openAppStorage();
      addTearDown(storage.close);
      final overlaySessions = await storage.conversations.sessions(
        origin: SessionOrigin.overlay,
      );
      expect(overlaySessions, hasLength(2), reason: 'zwei Overlay-Sitzungen');
      expect(
        await storage.conversations.sessions(origin: SessionOrigin.app),
        isEmpty,
      );
      final provider = FakeLlmProvider([ScriptedTurn.text('x')]);
      final e2eApp = E2eApp(
        storage: storage,
        startup: startup,
        config: (_) => deviceTestProviderConfig(provider),
      );
      await e2eApp.pump(tester);
      await pumpFor(tester, const Duration(seconds: 2));
      expect(find.textContaining(_mark), findsNothing);
      expect(find.textContaining('Berlin'), findsNothing);
      expect(find.textContaining('Kalender'), findsNothing);

      await askHost('unrole');
    },
    skip: !voiceE2e,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
