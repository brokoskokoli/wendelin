# WP132 – Zwei Build-Varianten: frei und Store (Vorbereitung, später)

**Zuordnung:** K102/K103. Entscheidung Maintainer 2026-10-22: Paket nur anlegen, noch nicht umsetzen. Die App soll später in zwei Varianten gebaut werden: **frei** (wie heute, alles drin; GitHub/privat) und **Store** (ohne inoffizielle Integrationen und mit store-tauglichen Ersatzwegen). Baut auf WP131 auf.

> **Vor Start abgleichen:** SMS/Anruf-Berechtigungen und Google-Tasks-OAuth gegen WP159 (eingeschränkte Einstellungen) und WP164 (Kontaktfelder) prüfen.

## Inhalt
1. **Varianten** als Android-Flavors bzw. Dart-Build-Schalter (`--dart-define=WENDELIN_VARIANT=store|free` plus Flavor für Manifest/Berechtigungen). Integrationen registrieren sich je Variante (`app/lib/di/integrations/registry.dart`); Code bleibt im Repo, die Store-APK enthält ihn nicht (Tree-Shaking prüfen) und das Manifest der Store-Variante enthält die Berechtigungen nicht.
2. **Store-Variante – Unterschiede:**
   - **Bring!:** weg (einzige inoffizielle API); Hinweis „als MCP-Server einbindbar“.
   - **SMS/Anruf:** ohne `SEND_SMS`/`CALL_PHONE`; stattdessen System-Dialog (SMS-App mit vorgefülltem Text, Wählfeld mit Nummer) – außer Google genehmigt die Ausnahme.
   - **Spotify:** ohne Web-API; „Spiel X“ über den Android-Standardbefehl „play from search“ an die Spotify-App (Wendelin sieht die Treffer nicht, keine Rückfrage, keine Warteschlange), Steuerung über die vorhandene allgemeine Mediensteuerung.
   - **Wake Word (Mikrofon-Vordergrunddienst), Akku-Ausnahme, Benachrichtigungszugriff (Medien):** bleiben, aber mit Begründungstexten/Demo für die Play Console; Akku-Ausnahme notfalls weglassen.
   - **Open-Meteo:** kostenlos nur nicht-kommerziell – bei kostenpflichtiger App Abo oder anderer Wetterdienst.
   - **Google Tasks:** OAuth-Prüfung bei Google (Datenschutzerklärung, Prüfvorgang).
   - Datenschutzerklärung (Seite + Link in der App), Play-Data-Safety-Angaben.
3. **Release-Workflow (WP131)** baut beide Varianten; Store-Variante als AAB (Play) und APK.
4. Prüfliste `docs/STORE.md` mit allen Play-Punkten (Stand bei Umsetzung neu prüfen, Richtlinien ändern sich).

## Abnahmekriterien
- [ ] Store-APK enthält weder Bring-Code noch `SEND_SMS`/`CALL_PHONE` (Test über `aapt dump permissions` bzw. check_apk), freie APK unverändert.
- [ ] Ersatzwege (SMS-Dialog, Wählfeld, Spotify „play from search“) mit Tests und E2E auf dem Emulator.
- [ ] `dart run tool/gate.dart --changed` grün, CI für beide Varianten grün, Review FREIGABE.

## Parallel-Hinweise
- Erst nach WP131 und nach dem großen Android-Gesamttest; Start nur mit Go des Maintainers.
