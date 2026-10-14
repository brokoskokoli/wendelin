# WP60 – „Wendelin lernt deine Stimme“: Einlernen und Kalibrieren in der App (`app/`)

Abhängig von: WP44 (Vorlagen-Port, Kalibrierfunktion, Feature-Kette). Bezug: K29 (bestätigt 2026-10-14).

## Inhalt
- **Einlernen (~3 min):** Assistent unter Einstellungen → Sprache → Wake Word (und optional im Onboarding nach dem Gesprächsschritt): Wendelin bittet 15–20 Mal um „Wendelin“ (Hinweise: nah, 1–2 m, leise/normal), zeigt Fortschritt und Pegel, verwirft zu leise/abgeschnittene Aufnahmen. Aus jeder Aufnahme wird sofort das Embedding berechnet; **das Rohaudio wird direkt verworfen** (nie gespeichert).
- **Kalibrieren (~30 min, optional, empfohlen):** „Handy hinlegen und normal weiterreden“: Die App sammelt Hintergrund-Embeddings (nur Embeddings, kein Audio, kein Transkript), fordert gelegentlich per Ton auf, „Wendelin“ zu sagen, und berechnet daraus die Schwelle (Kalibrierfunktion aus WP44). Abbrechbar; Fortschritt und Ergebnis („geschätzte Fehlalarme/h“) werden angezeigt. Bildschirm darf an bleiben (Wakelock nur in dieser Phase), Mikrofon-Indikator sichtbar.
- **Mehrere Personen:** weitere Sprecher einlernen (Name optional), einzeln löschbar; „Neu einlernen“ ersetzt die Vorlagen einer Person.
- **Speicher:** Vorlagen und Schwelle im `WakeTemplateStore` (lokal, verschlüsselt wie andere sensible Daten, nicht im Export – oder nur auf ausdrücklichen Wunsch), gelöscht über „Alles löschen“.
- **Test-Modus:** „Jetzt ausprobieren“ zeigt Treffer live (Kandidat / bestätigt durch Nachprüfung), ohne das Overlay zu öffnen.

## Abnahmekriterien
- [ ] Widget-Tests für Einlernen (gültige/ungültige Aufnahme, Abbruch, Fortschritt), Kalibrieren (Abbruch, Ergebnis), Sprecherverwaltung; Goldens.
- [ ] Test, dass kein Rohaudio gespeichert wird (Store/Dateisystem-Fake prüft nur Embeddings).
- [ ] Emulator: Einlernen mit eingespeisten WAV-Dateien (synthetische Stimme) und anschließender Treffer im Test-Modus (nur `Wendelin_AOSP_35`).
- [ ] Prüfliste für das echte Gerät (Maintainer): Einlernen, 30 min Kalibrieren, danach Trefferquote/Fehlalarme über einen Tag.

## Umsetzung (2026-10-14)
- **Merkmalskette:** `app/lib/platform/voice/ort_session.dart` (C-API-Anbindung, kein neues Paket), `onnx_wake_models.dart`, `wake_feature_chain.dart`; WP50 nutzt `wakeFeaturesFactoryProvider` (`app/lib/di/wake_providers.dart`).
- **Einstellung Nachprüfung:** `wakeVerifyProvider` (Standard an) schaltet Stufe 2 für den Alltag; der Test-Modus prüft immer und zeigt Kandidat und Bestätigung getrennt. WP50 liest den Schalter.
- **Schwelle:** Direkt nach dem Einlernen gilt die vorläufige Schwelle 0,85 (`wakeProvisionalThreshold`, Untergrenze von `calibrateThreshold`; Messung WP44: etwa 84 % Treffer bei 2,8 Kandidaten/h). Eine Schwelle aus Leave-one-out wäre unbrauchbar, weil Aufnahmen einer Stimme sich fast gleichen können (Ähnlichkeit 1,0, auf dem Emulator gemessen), während eine andere Äußerung derselben Stimme nur 0,83 erreicht. Die Kalibrierung speichert höchstens 0,95 (`calibrationMaxThreshold`).
- **Nicht umgesetzt:** Einlernen im Onboarding (optional laut Konzept); Mehrpersonen-Erkennung im Live-Dienst (WP50 baut aus `WakeTemplateStore` je Sprecher die Engine).
