// WP151: Speichern im Einlern-Bildschirm: Doppeltipp und Speicherfehler.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/wake_providers.dart';
import 'package:wendelin/ui/settings/settings_page.dart' show PrimaryButton;
import 'package:wendelin/ui/settings/wake/wake_enroll_screen.dart';
import 'package:wendelin/voice/wake/wake_storage.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../support/wake_support.dart';
import 'wake_word_screen_test.dart' show pumpWake, until, wakeEnv;

const _screen = WakeEnrollScreen(speakerId: 'a', name: 'Anna');

/// Secret store whose first write of templates fails.
final class FlakySecrets implements SecretStore {
  FlakySecrets(this.inner);
  final InMemorySecretStore inner;
  int templateWrites = 0;
  bool failFirst = false;

  /// Holds template writes back while set (saving takes a while).
  Completer<void>? gate;

  @override
  Future<String?> read(String key) => inner.read(key);

  @override
  Future<void> write(String key, String value) async {
    if (key.startsWith(SecretWakeTemplateStore.templatePrefix)) {
      templateWrites++;
      if (failFirst && templateWrites == 1) throw StateError('Speicher voll');
      await gate?.future;
    }
    await inner.write(key, value);
  }

  @override
  Future<void> delete(String key) => inner.delete(key);

  @override
  Future<Set<String>> listKeys() => inner.listKeys();
}

void main() {
  testWidgets('Doppeltipp auf Speichern: ein Speichern, kein Fehler', (
    tester,
  ) async {
    final secrets = FlakySecrets(InMemorySecretStore())
      ..gate = Completer<void>();
    final env = wakeEnv(
      audio: SequenceAudio([for (var i = 0; i < 15; i++) recording()]),
      extra: [
        wakeStoreProvider.overrideWithValue(SecretWakeTemplateStore(secrets)),
      ],
    );
    await pumpWake(tester, env, _screen);
    await until(tester, find.text('Speichern'));
    // Two taps before the next frame: the same callback runs twice.
    final press = tester
        .widget<PrimaryButton>(find.widgetWithText(PrimaryButton, 'Speichern'))
        .onPressed!;
    press();
    press();
    await tester.pump();
    expect(find.textContaining('gescheitert'), findsNothing);
    expect(find.byType(PrimaryButton), findsNothing, reason: 'beim Speichern');
    secrets.gate!.complete();
    await tester.pump(const Duration(seconds: 1));
    expect(secrets.templateWrites, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Speicherfehler: Meldung, erneutes Speichern klappt', (
    tester,
  ) async {
    final secrets = FlakySecrets(InMemorySecretStore())..failFirst = true;
    final env = wakeEnv(
      audio: SequenceAudio([for (var i = 0; i < 15; i++) recording()]),
      extra: [
        wakeStoreProvider.overrideWithValue(SecretWakeTemplateStore(secrets)),
      ],
    );
    await pumpWake(tester, env, _screen);
    await until(tester, find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await until(tester, find.textContaining('Das Einlernen ist gescheitert'));
    expect(find.textContaining('Sag jetzt'), findsNothing);
    expect(find.text('Speichern'), findsNothing, reason: 'Label mit Zahl');
    final again = find.text('Mit 15 Aufnahmen speichern');
    expect(again, findsOneWidget);
    await tester.tap(again);
    await tester.pump(const Duration(seconds: 1));
    expect(secrets.templateWrites, 2);
    expect(find.textContaining('gescheitert'), findsNothing);
  });
}
