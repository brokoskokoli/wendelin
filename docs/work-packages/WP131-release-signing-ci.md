# WP131 – Release-Signatur und automatischer APK-Build auf GitHub

**Zuordnung:** Verteilung (K102, K103). Entscheidung Maintainer 2026-10-22: Build auf ein sauberes eigenes Zertifikat umstellen; GitHub baut bei einer neuen Version automatisch die signierte APK und legt sie im Release ab. Start 2026-10-23, sobald der Maintainer das Zertifikat als Secret hinterlegt hat.

## Ausgangslage
- Release-Builds werden heute mit dem Debug-Schlüssel des Build-Rechners signiert (`app/android/app/build.gradle*`, `signingConfig = signingConfigs.getByName("debug")`). Der Schlüssel ist nicht gesichert; ein anderer Rechner kann keine Updates bauen.
- `tool/check_apk.sh` baut lokal `flutter build apk --release` und prüft die APK.

## Inhalt
1. **Signatur-Konfiguration:** `signingConfigs.release` liest Keystore-Pfad, Alias und Passwörter aus `key.properties` (lokal, gitignored) bzw. Umgebungsvariablen (CI). Fehlt beides → lokaler Build fällt wie heute auf Debug zurück, mit deutlicher Warnung; CI-Release-Build bricht ab (nie unsigniert oder debug-signiert veröffentlichen).
2. **Anleitung für den Maintainer** (`docs/RELEASE.md`): Keystore mit `keytool` erzeugen (RSA 4096, Gültigkeit ≥ 25 Jahre), Sicherung (Passwortmanager, zweiter Ort), als GitHub-Secrets hinterlegen (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`). SHA-256-Fingerabdruck des Zertifikats auslesen (für Googles Entwickler-Verifizierung: Fingerabdruck dort hochladen, Konto des Maintainers). Keystore nie ins Repo.
3. **Workflow `.github/workflows/release.yml`:** Auslöser Tag `v*` (z. B. `v0.6.0`) bzw. manuell. Schritte: Gate-Ergebnis des Commits grün (oder Gate laufen lassen), Versionsname/-code aus dem Tag (pubspec `version` prüfen), Rust-attest wie in `gate.yml`, `flutter build apk --release` (ggf. Split per ABI arm64 zuerst), `tool/check_apk.sh` auf der fertigen APK, APK + `SHA256SUMS` als GitHub-Release-Asset, Release-Notizen aus den Merges seit dem letzten Tag. Secrets nur in diesem Job, keine Ausgabe ins Log.
4. **Wechsel vom Debug-Schlüssel:** Bestehende Installationen (Maintainer) lassen sich nicht mit neuem Schlüssel aktualisieren → Anleitung: Daten sichern (vorhandenen Export prüfen: Einstellungen, Provider/Keys, Verläufe, Gedächtnis, Wake-Vorlagen; Lücken als Abweichung melden), deinstallieren, neue APK, wiederherstellen. Zeitpunkt: zusammen mit dem großen Gesamttest.
5. Lokale Test-APKs für den Maintainer (`~/ai/wendelin-testing`) danach aus demselben Release-Schlüssel bzw. aus dem GitHub-Release.

## Abnahmekriterien
- [ ] Probe-Tag auf einem Test-Tag (z. B. `v0.0.0-test`, danach löschen) erzeugt ein Release mit signierter APK; `apksigner verify --print-certs` zeigt den Release-Fingerabdruck, nicht den Debug-Schlüssel.
- [ ] Ohne Secrets bricht der Release-Job ab (Test/Probe); lokaler Build ohne `key.properties` warnt und nutzt Debug.
- [ ] Keine Secrets im Log, `key.properties`/`*.jks`/`*.keystore` in `.gitignore`, check_privacy grün.
- [ ] `dart run tool/gate.dart --changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- Berührt `app/android/app/build.gradle*`, `.github/workflows/`, `docs/`, `tool/check_apk.sh`. WP132 (Store-Variante) baut später auf diesem Workflow auf (zweite Variante als zweites Asset).
