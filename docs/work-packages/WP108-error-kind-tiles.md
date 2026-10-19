# WP108 – Fehlerart bis zur Integrationskachel durchreichen (`app/`, `packages/wendelin_integrations`)

**Zuordnung:** M5 (Folgepunkt aus WP105).

Bezug: WP105 zeigt in der Kachel-Fehlerzeile der Integrationen nur einen generischen Text („<Dienst> pausiert“), weil `onError` der Integrationen nur eine deutsche Meldung liefert und die Specs sie durch den Marker `pausedError` ersetzen (`app/lib/di/integrations/*_spec.dart`, `integration_spec.dart:12`). Beim „Erneut versuchen“ gibt es die Texte je Fehlerart schon (`app/lib/ui/settings/reconnect_text.dart`, `PortErrorKind`).

## Inhalt
1. `onError` der Integrationen (Bring!, Todoist, Google Tasks, Home Assistant, Spotify) liefert zusätzlich die Fehlerart (`PortErrorKind` oder gleichwertig), ohne dass die deutsche Meldung für Modell und Log verloren geht.
2. `reportError` und die Registry speichern die Fehlerart je Integration statt nur eines Strings. Die Kachel und die Einstellungsseiten zeigen den lokalisierten Text je Art (de/en/fr), z. B. Zugriff verweigert/abgelaufen, nicht erreichbar, Fehler. Der Bring!-Zustand `reauthError` aus WP107 bleibt erhalten.
3. Keine Tokens, URLs mit Geheimnissen oder Nutzerdaten in den Texten.

## Abnahmekriterien
- [ ] Unit-/Widget-Tests je Fehlerart und je Integration (Kachel und Einstellungsseite), mit Mutationsbeleg; l10n-Test de/en/fr.
- [ ] `clearError`/`onRecovered` setzen die Art zurück; „Erneut versuchen“ unverändert.
- [ ] Gerätetest-Punkte `docs/testing/m5/wp108.md`; E2E nur, wenn ohne Aufwand per Fake-Server (z. B. Fake-HA aus `run_ha`).
- [ ] Gate grün.
