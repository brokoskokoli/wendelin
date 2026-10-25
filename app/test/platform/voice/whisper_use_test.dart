// WP146: marks of the engines that use a shared Whisper model.

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/whisper_registry.dart';

void main() {
  const model = 'test-model';

  test('Nutzung markieren, zählen, abmelden; der Besitzer wird benachrichtigt',
      () async {
    var left = 0;
    watchWhisperUsers(model, () => left++);
    addTearDown(() => unwatchWhisperUsers(model));
    expect(await whisperUsers(model, 'app'), 0);

    markWhisperUse('overlay', model);
    expect(await whisperUsers(model, 'app'), 1);
    // The owner does not count itself.
    expect(await whisperUsers(model, 'overlay'), 0);

    unmarkWhisperUse('overlay', model);
    await pumpEventQueue();
    expect(await whisperUsers(model, 'app'), 0);
    expect(left, 1);
  });
}
