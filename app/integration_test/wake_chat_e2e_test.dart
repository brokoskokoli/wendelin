// Gerätetest WP93: Wake-Treffer bei sichtbarem Chat hört im Chat zu (mit
// dem Kontext der Unterhaltung), sonst öffnet das Overlay. Der Treffer
// kommt über den Debug-Hook `WakePlatform.debugHit` (nur Debug-Builds; der
// Dienst meldet einen Treffer wie nach dem Wake Word). Voraussetzung wie
// wake_service_e2e_test.dart: Rolle (Skript `role`), Stimme eingelernt.
//
//   WENDELIN_MODELS=~/wendelin-models \
//     tool/e2e_android.sh integration_test/wake_chat_e2e_test.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/di/wake_service.dart';
import 'package:wendelin/platform/wake/wake_platform.dart';
import 'package:wendelin/ui/routes.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'support/e2e.dart';
import 'support/voice_e2e.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (voiceE2e) await waitForDeviceFiles();
  });

  testWidgets(
    'Chat sichtbar: Zuhören im Chat; Einstellungen offen: Overlay',
    (tester) async {
      final app = E2eApp();
      final c = await app.pump(tester);
      await askHost('role');
      final service = c.read(wakeServiceProvider.notifier);
      await service.setCondition(WakeCondition.always);
      expect(await service.setEnabled(enabled: true), isTrue);
      final platform = WakePlatform();
      for (var i = 0; i < 60 && !(await platform.status()).running; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect((await platform.status()).running, isTrue);

      // Chat sichtbar: der Treffer startet das Zuhören im Chat.
      final triggers = <TriggerKind?>[];
      c.listen(voiceControllerProvider.select((v) => v.trigger), (_, t) {
        triggers.add(t);
      });
      expect(await platform.debugHit(), isTrue);
      for (var i = 0; i < 40 && !triggers.contains(TriggerKind.wakeWord); i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(triggers, contains(TriggerKind.wakeWord));
      // Ende des Zuges: der Dienst hört wieder (Status läuft weiter).
      await c.read(voiceControllerProvider.notifier).whenIdle;
      expect((await platform.status()).running, isTrue);

      // Einstellungen offen: kein Zuhören im Chat (das Overlay öffnet).
      triggers.clear();
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      unawaited(nav.pushNamed(AppRoutes.settings));
      await tester.pumpAndSettle();
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
