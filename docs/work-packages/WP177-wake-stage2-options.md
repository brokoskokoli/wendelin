# WP177 – Weckwort: Wählbare Stufe-2-Prüfer (Prüfer B und Spracherkennungsmodell mit ODER-Logik)

**Zuordnung:** K143 (ändert K138); Wunsch Maintainer 2026-10-29.

## Ziel
Die Nachprüfung des Weckworts (Stufe 2) soll in den Einstellungen flexibel konfigurierbar sein:
1. **Prüfer B (Stimmvorlagen):** Prüft ausschließlich gegen die eingelernten Stimmvorlagen bekannter Personen.
2. **Spracherkennungsmodell:** Prüft das Weckwort über das geladene Spracherkennungsmodell (Parakeet/Whisper). Geeignet für allgemeine Bereiche, in denen auch nicht trainierte Personen das Gerät ansprechen.

Beide Optionen können unabhängig voneinander aktiviert werden:
* **Beide aktiv (ODER-Logik):** Bestätigt einer von beiden, gilt das Weckwort als bestätigt (Prüfer B prüft zuerst schnell und sparsam; verneint B, prüft das Spracherkennungsmodell).
* **Nur Prüfer B:** Bestätigt ausschließlich bekannte Personen anhand der Vorlagen. Kein Rückfall auf das Erkennungsmodell.
* **Nur Spracherkennungsmodell:** Prüft rein das Sprachmodell ohne Vorlagenabgleich.
* **Beide inaktiv:** Stufe 2 ist komplett ausgeschaltet (Direktannahme aus Stufe 1).

Gilt einheitlich für alle Modi: Hintergrunddienst (Idle), Stationsmodus und Barge-in (Unterbrechen im Gesprächsmodus).

## Umsetzung
1. **`wendelin_voice`:**
   - `VerifierBWakeVerifier`: `fallback` optional; bei gesetztem Fallback greift die ODER-Logik (wenn B < Schwelle oder ohne Sequenzen, entscheidet der Fallback). Ohne Fallback lehnt B direkt ab.
   - `VerifierBBargeVerifier`: `fallback` optional; bei gesetztem Fallback entscheidet das Transkript bei B < Schwelle oder im Echo-Fall.
2. **Plattform & Engine:**
   - `WakeStage2Settings` (`verifierB`, `recognizer`, `active`).
   - `DeviceWakeParts.verifier`: Erzeugt Verifier nach gewählten Einstellungen.
   - `WakeHost`: Übergibt `verifierB` und `recognizer` an die Engine.
   - Android Kotlin `WakeSettings` / `runArgs`: Transportiert `verifyB` und `verifyModel`.
3. **DI & Einstellungen:**
   - `wakeVerifyBKey` (default `true`) und `wakeVerifyModelKey` (default `false`).
   - `wakeStage2Provider` mit `setVerifierB` und `setRecognizer`.
   - `wakeVerifyProvider` bildet `stage2Settings.active` ab (voll abwärtskompatibel).
   - `wakeBargeInDetectorProvider`: Nutzt die gewählte Prüfer-Kombination.
4. **UI & Lokalisierung:**
   - `WakeServiceSection`: Ersetzt den bisherigen Einzel-Switch durch zwei Zeilen mit Haken (`CheckStatusIcon.ok` bei aktiv), getrennt schaltbar.
   - Lokalisierung in de, en, fr (`l10n_merge.dart`).
5. **Lückenprüfung:**
   - `wakeStage2GapOf` berücksichtigt die aktiven Prüfer.

## Abnahmekriterien
- [x] Unit-Tests in `wendelin_voice` für `VerifierBWakeVerifier` und `VerifierBBargeVerifier` mit/ohne Fallback grün.
- [x] Widget-Tests in `app` für `WakeServiceSection` (Schalten beider Optionen) grün.
- [x] Bestehende Wake-Tests (`wake_host_test`, `wake_parakeet_test`, `wake_stage2_gap_test`) grün.
- [x] `gate.dart --changed` grün.
