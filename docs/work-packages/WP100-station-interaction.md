# WP100 – Stationsmodus: Gespräch, Wiedergabe und Kacheln (`app/`)

**Zuordnung:** M6. Nach WP99; braucht WP90 (Mediensteuerung) und WP92 (Sprecherrechte).

Bezug: Konzept Stationsmodus; K54, K62, K63.

## Inhalt
1. **Gespräch auf der Station:** Bei Wake Word zeigt die Station Transkript und Antwort groß, statt das Overlay zu öffnen. Ablauf über den gesperrten Agentenlauf (`app/lib/voice/locked_agent_run.dart`).
2. **Rechte:** Sprachbefehle nach der Freigabeliste K54 (`allowedWhileLocked` in `app/lib/di/integrations/integration_spec.dart`), erkannte Sprecher (WP92) mit ihren Rechten. Vorlesen von Terminen und Aufgaben auf Anfrage bleibt gesperrt.
3. **Wiedergabe:** aktueller Titel (Spotify WP84, Medien WP90) mit großen Knöpfen, ohne Entsperren bedienbar.
4. **Smart-Home-Kacheln:** selbst gewählte HA-Entitäten (WP91), ohne Entsperren antippbar im selben Umfang wie die Sprache. Schlösser, Alarm, Cover und Schalter mit „immer bestätigen“ sind nicht als Kachel wählbar.
5. **Gesprächsmodus länger:** Standard 15 s statt 5 s, einstellbar.

## Umsetzung
- Eine Policy-Funktion für Sprache und Kacheln (keine zweite Liste), damit beide nicht auseinanderlaufen.
- Parallel: WP101 (berührt Ton und Wecker, nicht die Policy).

## Abnahmekriterien
- [ ] Tests: Kachel für kritische Entität nicht wählbar und nicht ausführbar, auch nicht über manipulierte Einstellungen; Sprache und Kachel nutzen dieselbe Policy. Mutationsbeleg (Sicherheitslogik, Re-Review).
- [ ] Test: „was steht heute an?“ bei gesperrter Station wird abgelehnt, das Display zeigt die Titel trotzdem.
- [ ] E2E (Emulator): Fake-HA Licht per Kachel und Sprache, Medien-Knöpfe, Gespräch auf der Station bei gesperrtem Gerät. Gate grün.
