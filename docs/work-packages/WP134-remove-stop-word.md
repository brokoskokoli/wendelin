# WP134 – Stopp-Wort ausbauen, Vorlagen-Vergleich für „Wendelin“ zentrieren

**Zuordnung:** K107 (zu K23 c/d, K24 a; Inhalte aus WP64b, WP80, WP113, WP126). Entscheidungen Maintainer 2026-10-22: Das Stopp-Wort (Barge-in) wird komplett ausgebaut, unterbrochen wird nur noch mit „Wendelin“; das Thema Stopp ist beendet. Das gesprochene „Stopp“/„Ende“ aus dem Transkript (beendet den Gesprächsmodus) bleibt. Zentrieren der Embeddings und Vorlagen ohne Stille-Polster kommen ins selbe Paket.

## Anlass (Analyse WP126)
- Stopp nutzt nur Vorlagen und reinen Kosinus auf den openWakeWord-Embeddings. Diese sind nicht zentriert: Ein fester gemeinsamer Anteil trägt etwa 71 % der Energie, beliebiges Audio liegt untereinander bei ~0,74. Digitale Stille liegt fast auf dem Mittelwert (0,96); 3 von 16 Vorlagen sind Stille-Polster aus dem Einlernen (`wake_enroller.dart`).
- Gegen die Stopp-Vorlagen: Stille 0,87, Rauschen 0,85, „Wendelin“ 0,84, „Stopp“ 0,98 – Abstand ~0,12, Schwelle 0,70 unter dem Grundwert. Zentriert (synthetisch): Rauschen 0,0, Stille 0,20, „Wendelin“ 0,45, „Stopp“ 0,94.
- „Wendelin“ hat über die Vorlagen in Stille 0,82–0,83 bei thr 0,75 und könnte nach dem Warmstart auf Stille auslösen.

## Inhalt
### A. Ausbau Stopp-Wort (Barge-in)
- Entfernen: Einlernen von „Stopp“, gespeicherte Stopp-Vorlagen (Migration: beim Start löschen), Einstellung „Stopp schließt das Overlay“, `stopOverridesWake`, Stopp-Floor/sgap, Barge-in-Modus-Texte mit „Stopp“, `voice_stop_word_e2e_test`. Einstiege: `packages/wendelin_voice/lib/src/wake/` (`wake_word_barge_in.dart`, `barge_verifier.dart`, `candidate_wake_engine.dart`), `voice_pipeline*.dart`, `app/lib/voice/wake/wake_barge_in.dart`, `app/lib/ui/settings/wake/wake_word_screen.dart`, `memory_repository_impl.dart`.
- **Bleibt:** das Transkript-Stoppwort (`stop-word source=transcript`, beendet den Gesprächsmodus); Pegel-Gate und Ausschnitt-Fix aus WP126, soweit sie für „Wendelin“ gelten.
- Danach messen, wie gut die Unterbrechung allein mit „Wendelin“ funktioniert (E2E `voice_barge_in`, je 3×; Gerätetest-Block ins laufende Protokoll).

### B. Vorlagen-Vergleich zentrieren
- Embeddings vor dem Kosinus zentrieren (Mittelwert aus Hintergrund/Einlernen, Herleitung dokumentieren), Stille-Polster nicht mehr als Vorlage speichern, bestehende Vorlagen migrieren (Polster verwerfen, Mittel neu berechnen) oder Neueinlernen anbieten.
- Schwelle neu bestimmen und **auf den echten Aufnahmen messen** (Prüf-Split wie WP130, Stille/Rauschen/Verwechsler), Ergebnis in `docs/notes/wake-word-compare.md`. Test: Stille und Rauschen lösen nach dem Warmstart nicht aus.

## Abnahmekriterien
- [ ] Kein Code-Pfad mehr für Barge-in-Stopp; Transkript-Stopp unverändert (Test).
- [ ] Migration entfernt Stopp-Vorlagen und die Einstellung ohne Fehler (Test).
- [ ] Zentrierter Vergleich: Stille/Rauschen unter Schwelle, „Wendelin“-Treffer auf dem Prüf-Split mindestens wie vorher (Zahlen mit Intervallen, Plausibilität geprüft).
- [ ] Konzept-Abweichungen gemeldet; Gate `--changed`, CI grün, Review FREIGABE, E2E `voice_barge_in` 3× grün.

## Parallel-Hinweise
- Startet erst nach dem Merge von WP129 (gleiche Wake-Dateien). WP133 berührt nur `tool/train_wake_word/` und `docs/notes/`.
