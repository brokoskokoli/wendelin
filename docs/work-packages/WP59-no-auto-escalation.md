# WP59 – Kein automatischer Anbieterwechsel (Entscheidung Maintainer 2026-10-14)

Abhängig von: WP52 (Merge), danach sofort. Bezug: Konzept K28 (bestätigt), K27; ändert K8 d, K12 a, Teile von K10 c/K13.

## Entscheidung
Wählt der Nutzer ein Modell bzw. einen Anbieter (direkt, über ein Routing-Profil oder eine eigene Routing-Regel), antwortet **nur dieses Ziel**. Ist es nicht erreichbar, offline, überlastet, liefert es Fehler oder ist die Prüfung rot, zeigt Wendelin eine klare Fehlermeldung – es springt **nie automatisch** auf ein anderes Modell oder einen anderen Anbieter, auch nicht nach Rückfrage. Eine neue Anfrage des Nutzers („nochmal mit Claude“) bleibt möglich und folgt den normalen Regeln.

## Inhalt
- Agent-Laufzeit (`packages/wendelin_agent`, u. a. `agent_runner.dart`, `provider_resolver.dart`, `give_up_classifier.dart`, `routing/routing_engine.dart`): automatische Eskalation entfernen. Wiederholung beim **selben** Ziel nach wiederholbarem Fehler (1 Retry, K8 d) bleibt. Danach: `AgentFailed` mit verständlichem Grund (offline, nicht erreichbar, Zeitüberschreitung, Kontingent/Budget, Prüfung rot, Modell unbekannt).
- Einstellungen/Profile: Eskalationsketten (`routing.escalationChain`, Ketten je Routing-Profil aus K12 a) entfernen; gespeicherte Werte beim Laden ignorieren (Migration ohne Fehler). UI-Elemente für Ketten und die Eskalations-Rückfrage (gelbe Karte, K9 b) entfernen bzw. auf die verbleibenden Fälle reduzieren.
- „nochmal mit X“ (WP21) bleibt als ausdrückliche Nutzeranfrage; Datenschutz-Untergrenze und Taint (K13) gelten weiter: Liegt X unter der Untergrenze der Unterhaltung, fragt Wendelin wie bisher nach bzw. lehnt ab.
- Routing-Regeln, die der Nutzer selbst angelegt hat, wählen weiterhin das Ziel **vor** dem Aufruf (das ist seine Auswahl); sie wechseln nie nach einem Fehler.
- Texte der Fehlermeldungen (de/fr/en), gesprochen bei Sprach-Anfragen kurz („Claude ist gerade nicht erreichbar.“).
- Doku: Konzept-Abschnitte Routing/Eskalation und Agent-Schleife anpassen lassen (Orchestrator trägt ein), ADR bei Bedarf.

## Abnahmekriterien
- [ ] Tests: Ziel nicht erreichbar / 5xx / 429 / Timeout / Prüfung rot → genau ein Ziel wurde aufgerufen (plus höchstens ein Retry beim selben Ziel), danach `AgentFailed` mit Grund; nie ein Aufruf bei einem anderen Anbieter (Fake-Provider zählen Aufrufe).
- [ ] Alte Einstellungen mit Eskalationskette laden ohne Fehler und haben keine Wirkung.
- [ ] „nochmal mit X“ funktioniert weiter (Test).
- [ ] UI zeigt keine Ketten mehr; Fehlerkarte mit Grund (Widget-Test, Golden).
- [ ] Evals/Routing-Tabelle angepasst, Gate grün.
