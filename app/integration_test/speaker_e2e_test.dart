// Gerätetest WP92a (Sprechererkennung) mit synthetischen Stimmen: echtes
// CAM++-Modell (SherpaSpeakerEmbedder im Isolat) und der verschlüsselte
// Profilspeicher (SecretSpeakerProfileStore auf einem SecretStore, hier im
// Speicher, damit nichts im Schlüsselspeicher des Geräts bleibt).
//
// Modell und WAVs (16 kHz mono) liegen NICHT im Repo: Sie werden vorab in
// die App-Daten kopiert (`files/e2e/<Define>/`, siehe docs/testing/m5/
// wp92a.md und handoff/wp92a-e2e/prepare.sh). Ohne Define wird übersprungen.
//
//   WENDELIN_WP92A_DIR=wp92a \
//     tool/e2e_android.sh integration_test/speaker_e2e_test.dart
//
// Erwartete Dateien: das CAM++-.onnx (Name aus dem Katalog),
// {thorsten,kerstin}-enroll-1..5.wav, {thorsten,kerstin,miro}-test.wav.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/platform/voice/sherpa_speaker.dart';
import 'package:wendelin/ui/design/w_switch.dart';
import 'package:wendelin/ui/routes.dart';
import 'package:wendelin/ui/screens/main_screen.dart';
import 'package:wendelin/ui/settings/speaker/speaker_screen.dart';
import 'package:wendelin/voice/speaker/speaker_storage.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'support/e2e.dart';
import 'support/voice_e2e.dart';

const _dir = String.fromEnvironment('WENDELIN_WP92A_DIR');

Int16List _wav(String root, String name) =>
    Wav.parse(Uint8List.fromList(File('$root/$name.wav').readAsBytesSync()))
        .samples;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final skip = _dir.isEmpty
      ? 'WENDELIN_WP92A_DIR nicht gesetzt (siehe docs/testing/m5/wp92a.md)'
      : null;

  testWidgets(
    'Einlernen, Zuordnen, Fremdstimme, Löschen, Freigeben',
    (tester) async {
      final root = '${(await e2eDirectory()).path}/$_dir';
      final embedder = SherpaSpeakerEmbedder(
        model: SpeechModelCatalog.speakerCamPlus,
        directory: root,
      );
      addTearDown(embedder.release);
      final secrets = InMemorySecretStore();
      final identifier = SpeakerIdentifier(
        embedder: embedder,
        store: SecretSpeakerProfileStore(secrets),
      );
      Future<T> real<T>(Future<T> Function() f) async =>
          (await tester.runAsync(f)) as T;

      // (a) Thorsten und Kerstin einlernen, Kalibrierung ok.
      final ids = <String, String>{};
      for (final who in ['thorsten', 'kerstin']) {
        final r = await real(
          () => identifier.enroll(
            id: 'id-$who',
            name: who,
            samples: [
              for (var i = 1; i <= 5; i++) _wav(root, '$who-enroll-$i'),
            ],
          ),
        );
        ids[who] = r.profile.id;
        // ignore: avoid_print
        print(
          'WP92a enroll $who mean=${r.meanScore.toStringAsFixed(3)} '
          'min=${r.minScore.toStringAsFixed(3)} '
          'threshold=${r.profile.threshold.toStringAsFixed(3)} '
          'clamped=${r.thresholdClamped}',
        );
        // Synthetic voices are very consistent: clamped to the ceiling.
        expect(r.profile.threshold, inInclusiveRange(0.45, 0.60));
        expect(r.minScore, greaterThan(0.5));
      }
      expect(embedder.isLoaded, isTrue);
      expect(await real(identifier.profiles), hasLength(2));
      // Der Speicher enthält die Profile verschlüsselt-ablegbar (ein Schlüssel).
      expect(await secrets.listKeys(), {SecretSpeakerProfileStore.profilesKey});

      // (b) neue Testsätze: richtige Person.
      for (final who in ['thorsten', 'kerstin']) {
        final m = await real(
          () => identifier.identify(_wav(root, '$who-test')),
        );
        // ignore: avoid_print
        print(
          'WP92a identify $who -> ${m.name} score=${m.score?.toStringAsFixed(3)}',
        );
        expect(m.isKnown, isTrue, reason: '$who: $m');
        expect(m.personId, ids[who]);
      }

      // (c) Fremdstimme Miro: unknown.
      final miro = await real(
        () => identifier.identify(_wav(root, 'miro-test')),
      );
      // ignore: avoid_print
      print(
        'WP92a identify miro -> $miro score=${miro.score?.toStringAsFixed(3)}',
      );
      expect(miro.isKnown, isFalse);

      // (d) Löschen: danach unknown (eine Person, dann alle).
      await real(() => identifier.remove(ids['thorsten']!));
      final gone = await real(
        () => identifier.identify(_wav(root, 'thorsten-test')),
      );
      expect(gone.isKnown, isFalse);
      final kerstin = await real(
        () => identifier.identify(_wav(root, 'kerstin-test')),
      );
      expect(kerstin.personId, ids['kerstin']);
      await real(identifier.removeAll);
      final none = await real(
        () => identifier.identify(_wav(root, 'kerstin-test')),
      );
      expect(none.isKnown, isFalse);
      expect(none.reason, SpeakerUnknownReason.noProfiles);
      expect(await secrets.listKeys(), isEmpty);

      // (e) release() gibt das Modell frei; ein späterer Aufruf lädt neu.
      expect(embedder.isLoaded, isTrue);
      await real(identifier.release);
      expect(embedder.isLoaded, isFalse);
      final again = await real(
        () => embedder.embed(_wav(root, 'kerstin-test')),
      );
      expect(again.length, 192);
      expect(embedder.isLoaded, isTrue);
      await real(embedder.release);
      expect(embedder.isLoaded, isFalse);
    },
    skip: skip != null,
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'Seite Sprache → Sprechererkennung öffnet sich, Schalter ist aus',
    (tester) async {
      final app = E2eApp(startup: const StartupSettings(onboardingDone: true));
      await app.pump(tester);
      await pumpUntil(tester, find.byType(MainScreen));
      Navigator.of(tester.element(find.byType(MainScreen)))
          .pushNamed(AppRoutes.speaker);
      final sw = find.byType(WSwitch);
      await pumpUntil(tester, sw);
      expect(find.byType(SpeakerScreen), findsOneWidget);
      expect(tester.widget<WSwitch>(sw.first).value, isFalse);
    },
    skip: skip != null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
