# WP13 – Gemeinsame Schutzregel für sensible Inhalte (Folgepaket aus WP04/WP06)

Abhängig von: WP04, WP06 (gemergt). Konzept-Bezug: „Gedächtnis im Detail“ (keine Passwörter/Kartennummern), „Sicherheit“.

## Inhalt
- Die Erkennung sensibler Inhalte existiert doppelt und abweichend (`wendelin_storage/lib/src/sensitive_content.dart`, `wendelin_integrations/lib/src/memory/sensitive_content.dart`). Zusammenführen in **eine** reine Funktion in `wendelin_core` (`detectSensitiveContent(String) → SensitiveFinding?` mit Art und deutschem Grund), beide Pakete nutzen sie, Duplikate entfernen.
- Offene Review-Befunde aus WP04 mit erledigen:
  - IBAN-Falsch-Positive: „Flug LH12 um 14 Uhr 30 Gate 22 Sitz 14“ darf nicht erkannt werden (Leerzeichen nur zwischen Vierergruppen oder mod-97-Prüfung).
  - Optional: 13-stellige Ziffernfolgen, die mit 49/43 beginnen (Telefon ohne +), nicht als Karte werten.
  - Test für Luhn-gültige Folge mit führender 0/1 (soll nicht erkannt werden).
  - `basicAuth` u. ä. in der Redaktion (`auth` als letztes Wort im Schlüssel).
  - Überflüssiges `toLocal()` in `usage_repository_impl.dart:108` entfernen oder kommentieren.
- Tabellentests in core (alle bisherigen Fälle aus storage und integrations vereinigt, inkl. der Falsch-Positiv-Fälle), storage/integrations testen nur noch die Verwendung.

## Abnahmekriterien
- [ ] Eine Quelle in core, keine Duplikate mehr; beide Pakete nutzen sie.
- [ ] Alle bisherigen Erkennungsfälle beider Pakete grün, plus die neuen Falsch-Positiv-Fälle.
- [ ] Gate grün für core, storage, integrations; Abdeckung ≥ 85 %.
