# WP91 – Eigene Home-Assistant-Integration (`wendelin_integrations`, `app/`)

**Zuordnung:** M5.

Bezug: Wunsch Maintainer 2026-10-16/18. Nur Heimnetz bzw. über Tailscale (gleiche Adresse/MagicDNS); keine automatische Suche über Tailscale (mDNS), dann Adresse von Hand.

## Inhalt
1. Einrichtung: Adresse (http/https) + Long-Lived Access Token; automatische Suche per mDNS (`_home-assistant._tcp`) im WLAN. `http` nur für private Adressen (RFC 1918, Tailscale 100.64.0.0/10, `.local`, `*.ts.net`), sonst nur https.
2. Freigegebene Entitäten mit Namen/Räumen (Areas) auswählen; nur diese gehen ans Modell.
3. Tools: `ha__state` (r), `ha__call` je Domain mit Risiko: Licht/Schalter/Szenen/Medien w ohne Nachfrage mit Undo (vorheriger Zustand), Klima w mit Undo, Schloss/Alarm/Garage/Tor immer `e` (Bestätigung). `ha__list_entities` (r).
4. Bei Sprechererkennung (WP92) sind Licht/Szenen/Medien auch gesperrt erlaubt.

## Abnahmekriterien
- [ ] Unit-Tests mit Fake-HA (REST/WebSocket), Undo-Test, Risiko je Domain; Live-Test nur mit eigenem HA (übersprungen ohne Variablen).

## Gemeinsam für M5
- Neue Integration nach der Checkliste „Neue eingebaute Integration“ in `docs/ARCHITECTURE.md` (Ordner mit README, Port, `IntegrationSpec`, eine Zeile in der Registry, Einrichtungsseite). Risiko je Tool (r/w/e) nach Konzept, Undo wo möglich.
- Texte über das Lokalisierungssystem aus WP79 (de/en/fr). Läuft das Paket vor dem Merge von WP79, Texte deutsch; WP79 zieht sie nach.
- Geheimnisse (Tokens, Client-IDs des Nutzers) nur in `flutter_secure_storage`, nie im Repo, in Logs oder Exporten. Live-Tests sparsam, `@Tags(['live'])`.
- Emulator-Fixture bzw. E2E durch den separaten E2E-Agenten; Prüfpunkte für den Gerätetest in `docs/testing/m5-device.md` ergänzen. Gate grün.
