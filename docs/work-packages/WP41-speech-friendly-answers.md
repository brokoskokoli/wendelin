# WP41 – Vorlesefreundliche Antworten (`wendelin_agent`, `wendelin_voice`, wenig `app/`)

Abhängig von: **WP31** (gemeinsame Stellen in `voice_controller.dart`), **WP37** (zerlegter Agent-Runner). Bezug: Wunsch des Maintainers 2026-10-13, Konzept K19.

## Problem
Antworten sind für den Bildschirm geschrieben (Markdown, Listen, Doppelpunkte, Abkürzungen, „10:00“). `SpokenAnswer` entfernt heute nur Markdown und kürzt; das Vorgelesene klingt trotzdem oft hölzern („Termine Doppelpunkt …“, Aufzählungen ohne Satzbau).

## Inhalt
**Stufe 1 – Hinweis an das Modell (Standard)**
- Bei Sprach-Anfragen bekommt der Modellaufruf einen kurzen Stil-Hinweis: Die Antwort wird vorgelesen; kurze ganze Sätze, keine Überschriften, Tabellen oder Doppelpunkt-Aufzählungen, Listen als Satz („Milch, Brot und Eier“), Uhrzeiten/Daten/Zahlen sprechbar („um zehn Uhr“, „am Dienstag, dem 14.“), höchstens drei Sätze, Details nur auf Nachfrage.
- Der Hinweis steht im **dynamischen** Teil des System-Prompts (nach Datum/Gedächtnis, K8 e), damit der stabile Teil im Prompt-Cache bleibt. Getippte Anfragen bleiben unverändert.
- Gilt für alle Provider; Text-Anfragen und Eskalationen ohne Sprache bekommen ihn nicht.

**Stufe 2 – zwei Fassungen (Einstellung, Standard aus)**
- Einstellung „Antwort in zwei Fassungen“: Das Modell liefert zuerst einen kurzen Sprechtext in einem Block `<spoken>…</spoken>`, danach die geschriebene Antwort. Der Bildschirm zeigt nur die geschriebene Fassung, vorgelesen wird nur der Block.
- Der Block steht vorne, damit die Sprachausgabe beim Streamen sofort beginnen kann.
- Fehlt der Block oder ist er kaputt (kleine Modelle), fällt die App auf Stufe 1 zurück (`SpokenAnswer` aus der geschriebenen Antwort). Der Block wird nie angezeigt, nie in den Verlauf an andere Provider gegeben und zählt nicht als Antworttext für Gedächtnis-Vorschläge.

**Stufe 0 – lokale Aufbereitung (immer, als Netz)**
- `SpokenAnswer` ergänzen: Doppelpunkt am Satz-/Zeilenende → Satzende, „Label: Wert“-Zeilen als Satz, Uhrzeiten `10:00` → „10 Uhr“ (de) / „10 heures“ (fr) / „10 o'clock“ bzw. „10 a.m.“ (en), gängige Abkürzungen (z. B., ca., usw.) ausgeschrieben, Pfeile/Emojis entfernt. Zurückhaltend und sprachabhängig (de/fr/en).

## Abnahmekriterien
- [ ] Tabellentests Stufe 0 (de/fr/en): Doppelpunkte, Uhrzeiten, Abkürzungen, Label-Zeilen, Emojis.
- [ ] Stufe 1: Test, dass der Hinweis nur bei Sprach-Anfragen im dynamischen Prompt-Teil steht und der stabile Teil byte-gleich bleibt.
- [ ] Stufe 2: Parser für `<spoken>` im Stream (Block über mehrere Deltas, fehlender/unvollständiger Block → Rückfall), Anzeige ohne Block, Verlauf/Eskalation ohne Block.
- [ ] Modell-Eval: 10 Sprach-Befehle mit Haiku und dem Phala-Standardmodell, Anteil sauberer Sprechtexte (Stufe 1 und 2) im Bericht; Kosten-Mehrverbrauch von Stufe 2 gemessen.
- [ ] Einstellung unter Sprache mit Erklärung („mehr Tokens, natürlichere Sprache“).

## Offene Entscheidung
- Ob Stufe 2 später Standard wird, entscheidet der Maintainer nach der Eval (Kosten vs. Klang).

## Restrisiko
- Ein früherer Lauf mit Fremdinhalt (Web, Mail, Kalender von Dritten) kann über `memory__save` eingeschleusten Text speichern. Dieser steht später im System-Prompt, ohne dass Stufe 2 abgeschaltet wird.
- Das betrifft Prompt-Injection allgemein, nicht nur den Sprechtext.
- Stufe 2 ist standardmäßig aus.
- Mögliche spätere Abhilfe: die Herkunft eines Gedächtniseintrags beim Speichern festhalten (Lauf mit oder ohne Fremdinhalt) und Einträge aus unsicheren Läufen im Prompt kennzeichnen oder bestätigen lassen.
