// Gerätetest WP93: Wake-Treffer bei sichtbarem Chat hört im Chat zu (mit
// dem Kontext der Unterhaltung), sonst öffnet das Overlay. Der Treffer
// kommt über den Debug-Hook `WakePlatform.debugHit` (nur Debug-Builds; der
// Dienst meldet einen Treffer wie nach dem Wake Word). Voraussetzung wie
// wake_service_e2e_test.dart: Rolle (Skript `role`), Stimme eingelernt.
//
//   WENDELIN_MODELS=~/wendelin-models \
//     tool/e2e_android.sh integration_test/wake_chat_e2e_test.dart

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/debug/device_test_overrides.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/di/wake_providers.dart';
import 'package:wendelin/di/wake_service.dart';
import 'package:wendelin/platform/secure_secret_store.dart';
import 'package:wendelin/platform/voice/wav_audio_input.dart';
import 'package:wendelin/platform/wake/wake_platform.dart';
import 'package:wendelin/ui/routes.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin/voice/wake/wake_storage.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'support/e2e.dart';
import 'support/voice_e2e.dart';
import 'support/wake_enroll_e2e.dart';

final class _SwitchableAudio implements AudioInput {
  AudioInput? inner;

  @override
  bool get isRunning => inner?.isRunning ?? false;

  @override
  Stream<Int16List> start() => inner!.start();

  @override
  Future<void> stop() async => inner?.stop();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (voiceE2e) await waitForDeviceFiles();
  });

  testWidgets(
    'Chat sichtbar: Zuhören im Chat; Einstellungen offen: Overlay',
    (tester) async {
      final dir = await e2eDirectory();
      final enrollLog = captureVoiceLog();
      final audio = _SwitchableAudio();
      final provider = FakeLlmProvider([
        for (var i = 0; i < 6; i++) ScriptedTurn.text('ok'),
      ]);
      final app = E2eApp(
        config: (_) => deviceTestProviderConfig(provider),
        extraOverrides: [wakeAudioProvider.overrideWithValue(audio)],
      );
      await app.storage.settings.set(
        voiceSettingsKey,
        VoiceSettings(sttModel: 'whisper-base'),
      );
      final c = await app.pump(tester);
      {
        final nav0 = tester.state<NavigatorState>(find.byType(Navigator).first);
        unawaited(nav0.pushNamed(AppRoutes.wakeWord));
        await pumpUntil(tester, find.text('Aktivierungswort'));
        await tester.scrollUntilVisible(
          find.text('Stimme einlernen'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump(const Duration(seconds: 1));
        audio.inner = WavAudioInput.sequence(
          annaHeyClips('${dir.path}/wake'),
          speed: 4,
        );
        await tester.tap(find.text('Stimme einlernen'));
        await pumpUntil(tester, find.text('Weiter'));
        await tester.enterText(find.byType(TextField), 'Anna');
        await tester.tap(find.text('Weiter'));
        await pumpUntil(
          tester,
          find.text('Speichern'),
          timeout: const Duration(minutes: 3),
        );
        await tester.tap(find.text('Speichern'));
        expect(enrollLogProblem(enrollLog), isNull);
        await pumpUntil(tester, find.textContaining('15 Aufnahmen'));
        final speakers = await c.read(wakeSpeakersProvider.future);
        final real = SecretWakeTemplateStore(SecureSecretStore());
        await real.saveSpeakers(speakers);
        await real.save(
          (await c.read(wakeTemplatesProvider(speakers.single.id).future))!,
        );
        nav0.pop();
        await tester.pumpAndSettle();
      }
      await askHost('role');
      final service = c.read(wakeServiceProvider.notifier);
      await service.setCondition(WakeCondition.always);
      expect(await service.setEnabled(enabled: true), isTrue);
      final platform = WakePlatform();
      for (var i = 0; i < 60 && !(await platform.status()).running; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect((await platform.status()).running, isTrue);

      // Ein Gespräch besteht schon: der Wake-Zug setzt es fort.
      final agent = c.read(agentControllerProvider.notifier);
      await agent.send('Hallo vor dem Wake');
      List<ChatEntry> entries() => c.read(agentControllerProvider).entries;
      int starts() => entries().whereType<SessionStartEntry>().length;
      bool hasMessage() => entries().whereType<UserEntry>().any(
        (e) => e.text == 'Hallo vor dem Wake',
      );
      expect(hasMessage(), isTrue);
      final startsBefore = starts();

      // `whenIdle` wartet nicht, solange der Zug noch startet (keine Pipeline)
      // und ein zweiter Treffer startet den Zug neu: erst wenn Sprache und
      // Agent zwei Sekunden am Stück ruhen, ist der Zug wirklich vorbei. Sonst
      // läuft er in die Einstellungen hinein und zählt dort als Treffer.
      Future<void> turnOver() async {
        var quiet = 0;
        for (var i = 0; i < 120 && quiet < 4; i++) {
          await tester.pump(const Duration(milliseconds: 500));
          final v = c.read(voiceControllerProvider);
          final busy =
              v.active || v.followUp || c.read(agentControllerProvider).running;
          quiet = busy ? 0 : quiet + 1;
        }
        expect(quiet, 4, reason: 'Der Zug endet');
      }

      // Chat sichtbar: der Treffer startet das Zuhören im Chat.
      final triggers = <TriggerKind?>[];
      // Das Feld `trigger` bleibt nach einem Zug stehen: zählt nur ein
      // aktiver Zug mit Wake-Auslöser (auch beim zweiten Treffer).
      c.listen(voiceControllerProvider, (_, v) {
        if (v.active) triggers.add(v.trigger);
      });
      expect(await platform.debugHit(), isTrue);
      for (var i = 0; i < 40 && !triggers.contains(TriggerKind.wakeWord); i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(triggers, contains(TriggerKind.wakeWord));
      // Ende des Zuges: der Dienst hört wieder (Status läuft weiter).
      await turnOver();
      expect((await platform.status()).running, isTrue);
      // Dieselbe Sitzung: kein session-new, die Nachricht bleibt sichtbar.
      expect(starts(), startsBefore);
      expect(hasMessage(), isTrue);

      // Zweiter Treffer: wieder im Chat (der Dienst hörte wieder zu).
      triggers.clear();
      expect(await platform.debugHit(), isTrue);
      for (var i = 0; i < 40 && !triggers.contains(TriggerKind.wakeWord); i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(triggers, contains(TriggerKind.wakeWord));
      await turnOver();
      expect((await platform.status()).running, isTrue);
      expect(starts(), startsBefore);

      // Einstellungen offen: kein Zuhören im Chat (das Overlay öffnet).
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      unawaited(nav.pushNamed(AppRoutes.settings));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      triggers.clear();
      expect(await platform.debugHit(), isTrue);
      await tester.pump(const Duration(seconds: 5));
      expect(triggers, isNot(contains(TriggerKind.wakeWord)));
      await askHost('back');
      await service.setEnabled(enabled: false);
    },
    skip: !voiceE2e,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
