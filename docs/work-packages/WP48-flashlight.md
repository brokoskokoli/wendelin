# WP48 – Taschenlampe (`packages/wendelin_integrations/lib/src/flashlight/` + Kotlin-Kanal)

Abhängig von: – (sofort startbar). Bezug: K16. Checkliste „Neue eingebaute Integration“ in `docs/ARCHITECTURE.md`. Andockpunkte: `base_tool.dart`/`tool_args.dart` (`packages/wendelin_integrations/lib/src/common/`), `UndoManager`, `PlatformPorts` (`app/lib/platform/platform_ports.dart`), `app/lib/di/integration_specs.dart` (Merge-Hotspot, nur anhängen), Kotlin unter `app/android/app/src/main/kotlin/app/wendelin/` (Registrierung in `WendelinActivity.kt`), Texte in `app/lib/ui/screens/labels.dart`.

## Inhalt
- Integration `flashlight`, Tools `flashlight__on`, `flashlight__off`, `flashlight__toggle`. Risiko `write` mit Undo (vorheriger Zustand), ohne Nachfrage, nicht sensibel, alle Datenschutzstufen, kein Netz.
- Port `TorchPort` (`isAvailable`, `state`, `set(bool)`). Fehlerfälle: keine Blitz-LED, Kamera belegt, Thermik-Sperre. Daraus wird ein Tool-Fehler mit Kurztext, kein Absturz.
- Kotlin `TorchChannel` mit `CameraManager.setTorchMode` und `registerTorchCallback` (Zustand auch, wenn die Systemkachel umschaltet). Keine `CAMERA`-Berechtigung nötig; das wird im Test bzw. Bericht belegt.
- Ordner-README (Tools, Risiko, Berechtigungen, Plattformen). Die Ausnahme fürs gesperrte Gerät kommt in WP53. Hier nur das Flag `allowedWhileLocked` an der Integration (bzw. eine kleine Liste in der App), das WP53 nutzt.

## Abnahmekriterien
- [ ] Tool-Tests mit `FakeTorchPort`: an/aus/umschalten, Undo stellt den vorherigen Zustand her, keine LED → Tool-Fehler mit Text, Risiko `write` ohne Bestätigung.
- [ ] Contract-Suite `torchPortContract` in `testing.dart`.
- [ ] Kanal-Test mit Mock-Handler (`app/test/platform/`), Verdrahtung in `app/test/di/wiring_test.dart`.
- [ ] Emulator (`Wendelin_AOSP_35`): Der Pfad „keine LED“ ergibt eine saubere Fehlermeldung in der Tool-Karte (Text-Anfrage „Taschenlampe an“ mit Fake-Provider bzw. Demo-Modus).
- [ ] Gate grün, `tool/check_apk.sh` grün, Manifest ohne neue Berechtigung.

## Prüfliste für den Maintainer (echtes Telefon)
- [ ] „Taschenlampe an“ / „aus“ / „umschalten“ per Text und Stimme; Rückgängig auf der Karte schaltet zurück.
- [ ] Taschenlampe über die Systemkachel einschalten, dann „Taschenlampe aus“ → aus (Zustand wird erkannt).
