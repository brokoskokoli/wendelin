# WP18 – Standard-Assistent, Overlay, Push-to-talk, Vault-Zugriff (`app/` + Kotlin)

Abhängig von: WP15, WP16, WP17. Konzept-Bezug: „Auslöser“, „Oberflächen → Assistenten-Overlay“, „Einstellungen → Sprache/Assistent“, Design `screens/overlay*`.

## Inhalt
- **Standard-Assistent**: `VoiceInteractionService` + `VoiceInteractionSessionService` + Session (Kotlin, minimal), Metadaten-XML; die Session startet die Flutter-Overlay-Activity (transparentes Theme, halber Bildschirm) und triggert `TriggerSource.assistant`. Einstellung führt zu `Settings.ACTION_VOICE_INPUT_SETTINGS` bzw. Assistenten-Auswahl.
- **Overlay** laut `docs/design/screens/overlay.html`/PNG: Kopf (Marke + ProviderChip + CheckStatus), Live-Transkript, Wellenform, ToolResultCard mit Undo, Antwort, Steuerleiste (Tastatur · Mic · Beenden), Bestätigungskarte (gleiches Sheet), Hinweis Gesprächsmodus (ausgegraut bis M4). Golden gegen PNG.
- **Push-to-talk** im Hauptbildschirm (MicButton aktiv, Zustände idle/listening/thinking), Abbruch durch Antippen; Bestätigungen per Stimme („ja/nein“ – Transkript-Erkennung de/fr/en) oder Tap.
- **Vault-Zugriff**: `VaultPort` per SAF-Tree (`ACTION_OPEN_DOCUMENT_TREE`, persistente Rechte), besteht die Contract-Suite (Mock-Kanal); Einstellungen → Obsidian: Vault wählen, Tagesnotiz-Ordner/Format, Index aufbauen (Fortschritt).
- Integrationen-Seite: Obsidian mit Zustand/Einrichten.

## Abnahmekriterien
- [ ] Kotlin-Service registriert sich als Assistent (Manifest + XML), Instrumentationstest oder adb-Prüfung auf dem Emulator (`settings get secure assistant`/`voice_interaction_service` nach Setzen).
- [ ] Overlay-Golden gegen PNG; Widget-Tests für Push-to-talk-Ablauf mit Fakes (Audio→STT→Agent→TTS).
- [ ] Stimm-Bestätigung ja/nein tabellengetestet.
- [ ] SAF-VaultPort besteht Contract-Suite (Mock-Kanal).
- [ ] Gate grün, APK baut.
