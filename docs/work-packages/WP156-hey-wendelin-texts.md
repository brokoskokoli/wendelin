# WP156 – „Hey Wendelin“ konsequent in Texten und Doku

**Zuordnung:** Entscheidung Maintainer 2026-10-26 (Nachtrag K115): überall „Hey Wendelin“ nennen, damit Nutzer es so sagen. Die Erkennung nimmt vorerst weiter beide Wörter an; eine Hey-Pflicht folgt erst nach Daten aus WP155. Bestandsaufnahme vom 2026-10-26 (Orchestrator).

## Inhalt
- **App-Texte** (Fragmente unter `app/lib/l10n/src/`, de/en/fr, danach `dart run tool/l10n_merge.dart`): Alle Stellen, die „Wendelin“ als zu sprechendes Wort nennen, auf „Hey Wendelin“ (bzw. `{word}`) umstellen. Bekannt (de): `main/main_de:161`, `onboarding/onboarding_de:14`, `voice/voice_de:62`, `wake/wake_de:17, 36, 49, 92, 127, 234, 264, 295, 346, 373` (373 widerspricht heute dem tatsächlichen Einlerntext), en/fr an denselben Schlüsseln. Der App-Name „Wendelin“ (z. B. „Wendelin hört mit“, Manifest, „Wendelin lernt deine Stimme“) bleibt.
- **Benachrichtigung des Dienstes:** `WakeNotifications.kt:29,71` nennt fest auf Deutsch „Wendelin“ → „Hey Wendelin“, möglichst aus den App-Texten (Sprache des Nutzers) statt fest verdrahtet.
- **Weckwort-Rest:** Die Gruß-Liste in `stripWakeWord` (`packages/wendelin_voice/lib/src/wake/wake_verifier.dart:210`) an `heyWords` (`:99`) angleichen, damit bei „Hei/Hej/Hay Wendelin …“ der Gruß mit entfernt wird (heute bleibt der ganze Text stehen). Kein Eingriff in die Annahme-Logik.
- **Doku:** Testanleitungen, die „Wendelin“ als gesprochenes Weckwort nennen (`docs/testing/m4-device.md`, `docs/testing/m5/wp113.md`, `wp120.md`, `wp123.md`, `wp129.md`, `wp134.md`, `wp140.md`), auf „Hey Wendelin“; Altbefunde als solche lassen. `docs/adr/0016-barge-in-gespraechsmodus.md` Nachtrag. Das Konzept zieht der Orchestrator nach.
- Ein Check (Test über die l10n-Fragmente): Ein in Anführungszeichen gesetztes „Wendelin“ ohne „Hey“ davor kommt nicht mehr vor (Allowlist für den App-Namen).

## Abnahmekriterien
- [ ] Alle genannten Stellen umgestellt, Check mit Negativtest (Mutationsbeleg).
- [ ] Benachrichtigung zeigt „Hey Wendelin“ in der App-Sprache (Test bzw. E2E-Screenshot).
- [ ] `stripWakeWord` entfernt „Hei Wendelin“ & Co. (Tests), sonst unverändertes Verhalten.
- [ ] Goldens auf macOS aktualisiert, `--changed` grün, CI grün, Review FREIGABE.

## Nicht im Paket
- Hey-Pflicht in Stufe 1, Prüfer B, hw2 oder beim Unterbrechen (nach WP155).

## Parallel-Hinweise
- `wake_de.arb` & Co. berühren auch WP151/WP155: Texte nur an den genannten Schlüsseln ändern; nach WP151 starten.
