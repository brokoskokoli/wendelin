// WP145: the overlay closes in two parts: the host is released at once (the
// activity ends, the wake word listens again), the engine lives on without a
// window until the teardown reports. In that time a trigger (assist button,
// wake word) can still reach Dart; it must not read the disposed container.
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/core_providers.dart';
import 'package:wendelin/ui/overlay/assistant_overlay.dart';
import 'package:wendelin_core/testing.dart';

import '../support/test_env.dart';
import 'assistant_overlay_test.dart' show FakeAssistantPlatform, pumpOverlay;

void main() {
  testWidgets('echter Teardown: Trigger danach liest den Container nicht', (
    tester,
  ) async {
    AssistantOverlayScreen.tearDownEngine =
        AssistantOverlayScreen.defaultTearDown;
    final platform = FakeAssistantPlatform();
    final c = await pumpOverlay(
      tester,
      TestEnv(providerConfig: scripted(FakeLlmProvider(const []))),
      platform,
      autoStart: false,
    );
    await platform.closeHandler!();
    await tester.pump();
    expect(platform.calls, ['releaseHost', 'teardownDone']);
    expect(
      () => c.read(clockProvider),
      throwsStateError,
      reason: 'Container ist freigegeben',
    );

    platform.trigger();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Trigger während des Teardowns (Container weg, Host frei)', (
    tester,
  ) async {
    final platform = FakeAssistantPlatform();
    AssistantOverlayScreen.tearDownEngine = (container, _) async {
      container.dispose();
      platform
        ..trigger()
        ..trigger();
      await tester.pump(const Duration(milliseconds: 50));
    };
    await pumpOverlay(
      tester,
      TestEnv(providerConfig: scripted(FakeLlmProvider(const []))),
      platform,
      autoStart: false,
    );
    await platform.closeHandler!();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(platform.calls, ['releaseHost', 'teardownDone']);
  });
}
