# WP159 – Einrichtung: GPU-Prüfung nur mit Nachweis, Hinweis auf „Eingeschränkte Einstellungen“

**Zuordnung:** Gemeldete Fehler des Maintainers vom 2026-10-23 (STATUS „Nächste Schritte“ 3a/3b).

## Befunde
- (a) Im Anbieter-Setup (Abschluss-Schritt) erscheint die Auswahl „GPU-Prüfung über NVIDIA“ (aus/vorher/nachher), auch wenn der Anbieter bzw. das Modell keinen GPU-Nachweis liefert (z. B. Phala). `app/lib/ui/settings/provider_setup/finish_step.dart:48` zeigt `GpuCheckSection` nach `attested`, unabhängig von `noGpuEvidence` (Z. 41, gesetzt in `provider_setup_screen.dart:341` aus `gpuEvidence`, ermittelt in `app/lib/di/provider_setup.dart:269-281`). Die Auswahl ergibt dann keinen Sinn.
- (b) SMS-Berechtigungen und der Benachrichtigungszugriff (Musik, Benachrichtigungen lesen/antworten/steuern) lassen sich bei Installation per APK nicht aktivieren („aus Sicherheitsgründen nicht zugelassen“). Vermutete Ursache: Android 13+ „Eingeschränkte Einstellungen“ für Apps aus nicht sitzungsbasierten Installern. Freigabe nur über App-Info → ⋮ → „Eingeschränkte Einstellungen zulassen“ (der Menüpunkt erscheint erst nach einem gescheiterten Versuch). Die App erklärt das nirgends. Beteiligte Stellen: `MediaListenerService.kt`, `MediaChannel.kt`, `ContactsChannel.kt`, `AndroidManifest.xml`; App-Infos öffnen gibt es schon in `BatteryChannel.kt:40`.

## Inhalt
- **Teil A (GPU):** Auswahl nur zeigen, wenn ein GPU-Nachweis vorliegt (`gpuEvidence == true`); bei `false` nur den vorhandenen Info-Hinweis, bei `null` (unbekannt) Verhalten festlegen und begründen. Gespeicherter Modus bei fehlendem Nachweis: sinnvoll auf „aus“ bzw. nicht wirksam, ohne bestehende Profile still umzustellen, die einen Nachweis haben. Prüfen, ob es weitere Stellen mit GPU-Auswahl gibt (Profil-Einstellungen, `app/test/settings/gpu_per_profile_test.dart`) und dort gleich behandeln.
- **Teil B (Eingeschränkte Einstellungen):** Ursache zuerst belegen (Emulator Android 15: Installation per `adb install` vs. Session-Installer, `AppOpsManager`-Op `ACCESS_RESTRICTED_SETTINGS` bzw. Verhalten von Berechtigungsanfrage/Listener-Einstellung). Dann Sperre erkennen (SMS-Berechtigung dauerhaft abgelehnt bzw. Listener nach Rückkehr aus den Einstellungen nicht aktiv) und eine Schritt-für-Schritt-Anleitung mit Knopf zu den App-Infos zeigen, an den Stellen, an denen der Nutzer SMS bzw. Benachrichtigungszugriff einschaltet. Texte über l10n (de/en/fr wie im Bestand). Gerätezugriff nur über Ports bzw. `app/lib/platform/`.

## Abnahmekriterien
- [ ] A: Widget-Test: ohne GPU-Nachweis keine GPU-Auswahl, mit Nachweis vorhanden; Mutationsbeleg.
- [ ] A: Verhalten bei `gpuEvidence == null` und bei bestehenden Profilen dokumentiert und getestet.
- [ ] B: Ursache am Emulator belegt (Log bzw. Beobachtung in der Fertigmeldung), oder klar als nicht reproduzierbar gemeldet.
- [ ] B: Hinweis mit Knopf zu den App-Infos erscheint bei gesperrter SMS-Berechtigung und bei nicht aktivierbarem Benachrichtigungszugriff (Tests, Mutationsbeleg); Knopf öffnet die App-Infos (E2E oder Kanaltest).
- [ ] Gerätetest-Anleitung `docs/testing/m5/wp159.md` (APK-Installation, Freigabe über „Eingeschränkte Einstellungen“, Anbieter ohne/mit GPU-Nachweis).
- [ ] `--changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- Läuft allein. Berührt Einrichtung/Einstellungen und Android-Kanäle, nicht den Sprach-Controller.
