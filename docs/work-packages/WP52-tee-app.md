# WP52 – TEE in der App: Phala-Einrichtung, Status je Antwort, Prüfprotokoll

Abhängig von: WP46 (a und b), WP47, WP49; WP38 gemergt. Andockpunkte: Provider-Einrichtung `app/lib/ui/settings/provider_setup_screen.dart`, `app/lib/di/provider_setup.dart`, `ProviderFactory` (`packages/wendelin_providers/lib/src/provider_factory.dart`), Phala-Vorlage (`teeModelsOnly`), `ConversationReducer` (`app/lib/agent/conversation_reducer.dart`), Gesprächsansicht `app/lib/ui/screens/conversation_view.dart`, Design-Bausteine `app/lib/ui/design/`, Einstellungen/Routen (`app/lib/ui/routes.dart`, `app/lib/ui/settings/settings_screen.dart`), „Alles löschen“. Design: `docs/design/DESIGN.md`.

## Inhalt
- Einrichtung Phala: Modelle über `GET /v1/models`, nur `is_tee: true` wählbar (Vorlage `teeModelsOnly`). Erste Attestierung direkt beim „Testen“ mit Ergebnis je Stufe. Profil wird mit `AttestedProvider` gebaut. Optionen: „Bei fehlgeschlagener Prüfung auf … ausweichen“ (Standard aus), GPU-Prüfung über NRAS (nur falls vom Maintainer gewünscht, Standard aus).
- Status je Antwort im Gespräch: kleines Schild grün/gelb/rot mit Text für Screenreader („geprüft“, „wird geprüft“, „Prüfung fehlgeschlagen“). Tipp öffnet den Protokolleintrag. Rot zeigt zusätzlich eine Warnkarte und sperrt den Provider bis zur neuen Attestierung („Neu prüfen“).
- Hinweis bei Pinning-Wechsel: „Anbieter hat ein Update ausgerollt, neu geprüft“ (Konzept).
- Seite „Prüfprotokoll“ (Einstellungen → Datenschutz): Liste je Anfrage (Zeit, Provider, Modell, Keyset-Digest/ID, Commit, Ergebnis je Stufe, Quittungs-ID), Filter nach Status, Export als JSON (Teilen-Intent, Datei ohne Inhalte), Löschen.
- Sitzungs-Attestierung beim App-Start im Hintergrund vorwärmen, wenn ein Phala-Profil aktiv ist und Netz vorhanden ist.

## Abnahmekriterien
- [ ] Reducer-Tests: `AttestationStatusChanged` setzt den Status am richtigen Schritt, auch wenn er nach dem Ende der Antwort kommt. Ein gelber Zwischenstand wird zu grün oder rot.
- [ ] Widget-/Golden-Tests: Schild in drei Zuständen (hell/dunkel), Warnkarte, Prüfprotokoll-Liste und Detail, Einrichtungsergebnis je Stufe.
- [ ] Export-Test: JSON enthält keine Prompt-/Antwortinhalte und keine Keys.
- [ ] Emulator (`Wendelin_AOSP_35`): Text-Anfrage an ein Phala-Profil mit Fixture-Transport (Debug-Überschreibung) → grün. Manipulierte Quittung → rot und Sperre. Optional Live (`WENDELIN_LIVE`, kleinstes TEE-Modell) → grün.
- [ ] `docs/ARCHITECTURE.md` (Datenfluss, Ports) nachgeführt. Gate grün, APK baut.

## Prüfliste für den Maintainer (echtes Telefon)
- [ ] Phala-Profil einrichten, drei Fragen (eine mit Tool, z. B. Kalender) → jede Antwort grün, Prüfprotokoll zeigt alle Stufen.
- [ ] Flugmodus direkt nach einer Antwort → gelb, nach Rückkehr des Netzes grün bzw. nach 3 Versuchen rot.
- [ ] Prüfprotokoll exportieren und die Datei ansehen: keine Inhalte.

## Nachtrag (Maintainer 2026-10-14)
- Einstellung „GPU-Prüfung über NVIDIA“: Aus (Standard) / Vorher / Nachher mit kurzer Erklärung (Netzaufruf an NVIDIA, keine Inhalte). Bei „Nachher“ und fehlgeschlagener Prüfung: System-Benachrichtigung + roter Status an der Antwort und im Prüfprotokoll; folgende Anfragen an den Knoten fragen vorher nach. Bei „Vorher“ und Fehler: Hinweis mit „Ohne GPU-Prüfung senden“ (nur diese Anfrage) oder Abbrechen.
