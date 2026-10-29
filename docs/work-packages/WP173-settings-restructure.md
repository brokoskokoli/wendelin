# WP173 – Einstellungen umbauen: Routing unter Anbieter, „Erweiterte Einstellungen“, Sprache und Weckwort getrennt

**Zuordnung:** Wunsch des Maintainers vom 2026-10-28 (Vorbereitung für den Einrichtungsassistenten WP174).

## Wunsch (sinngemäß)
1. Der Menüpunkt **Routing** verschwindet aus dem Hauptmenü der Einstellungen; er bleibt unter **Anbieter** verlinkt (ein Klick mehr ist in Ordnung).
2. Auf der Anbieter-Seite fällt der Hinweistext oben weg („… standardmäßig, falls kein Routing aktiviert wird“).
3. Die Abschnittsüberschrift „Anbieter“ über dem Routing-Eintrag heißt künftig **„Erweiterte Einstellungen“**.
4. Der Menüpunkt **Sprache** wird aufgeteilt in **Sprache** und **Weckwort**: Die Weckwort-Einstellungen bekommen einen eigenen Einstellungspunkt.
5. Im Weckwort-Menü steht **ganz oben** der Download des von uns trainierten Weckwort-Modells. Das Weckwort lässt sich nur einschalten, wenn dieses Modell geladen ist.
- Alle Texte in de/en/fr (ARB), Begriffe nach `docs/GLOSSARY-l10n.md` („Hey Wendelin“, Weckwort/wake word).

## Abnahmekriterien
- [ ] Widget-Tests für Menüstruktur (Routing nicht im Hauptmenü, unter Anbieter erreichbar; Überschrift; Text weg; Weckwort eigener Punkt; Einschalten ohne Modell nicht möglich bzw. führt zum Download), Mutationsbelege; Goldens aktualisiert (nur macOS).
- [ ] Bestehende Deep-Links/Routen (`AppRoutes`) und Verweise aus anderen Seiten (z. B. Hinweise aus WP171) zeigen auf die neue Weckwort-Seite.
- [ ] `--changed` grün, CI grün, Review FREIGABE; E2E nur falls Routen von Integrationstests berührt werden.

## Parallel-Hinweise
- WP171 (Weckwort-Prüfung, Hinweis mit Download-Knopf) und WP172 (Overlay) laufen ggf. noch: WP173 startet nach WP171, weil beide die Weckwort-Einstellungen berühren. WP174 (Einrichtungsassistent) baut auf WP173 auf.
