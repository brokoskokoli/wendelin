import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/attestation_hub.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/ui/attestation/attestation_texts.dart';
import 'package:wendelin/ui/attestation/stage_explanations.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/fakes.dart';

void main() {
  group('Rückschrittschutz im Speicher (K59)', () {
    test('Untergrenze bleibt je Profil erhalten', () async {
      final storage = openInMemoryStorage();
      addTearDown(storage.close);
      final store = SettingsReleaseFloorStore(storage.settings);
      expect(await store.load('a'), isNull);
      final floor = ReleaseFloor(
        version: ReleaseVersion.tryParse('v0.0.159')!,
        integratedTime: 1789000500,
      );
      await store.save('a', floor);
      expect(await store.load('a'), floor);
      expect(await store.load('b'), isNull);
    });

    test('ein beschädigter Eintrag zählt als keine Untergrenze', () async {
      final storage = openInMemoryStorage();
      addTearDown(storage.close);
      await storage.settings.set(AppSettings.releaseFloor('a'), {
        'version': 'x',
      });
      expect(
        await SettingsReleaseFloorStore(storage.settings).load('a'),
        isNull,
      );
    });
  });

  test('jede Prüfstufe hat Namen und Erklärung in der App', () {
    final l = AppLocalizationsDe();
    for (final s in AttestationStage.values) {
      expect(stageLabel(l, s.id), isNot(s.id), reason: 'Name ${s.id}');
      // „gpu.evidence“ hat bewusst keine Erklärung (eigener Hinweis, WP82).
      if (s != AttestationStage.gpuEvidence) {
        expect(stageExplanationFor(l, s.id), isNotNull, reason: s.id);
      }
    }
  });
}
