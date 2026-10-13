# WP35 – R1: Agenten-Tooling, Architekturkarte, Größenregeln (`tool/`, Doku)

Abhängig von: – (sofort startbar auf main, kollidiert mit keinem laufenden Paket). Übersicht und Grundregeln: `R-refactoring.md`. Bezug: Gutachten **H4** (Gate-Ausgabe, Teilmodus), **M5** (Architekturkarte, veraltete Doku), **H1** (Größe der Review-Einheit), Abschnitt 6 (Quick Wins 1–6), **N4** (Goldens nur auf macOS), **N5** (plattformabhängige Tests), **N3** und **N7** (als Teil der Karte). Andockpunkte: `tool/gate.dart` (`step`, Paketschleife, App-Schritte), `tool/check_deps.dart` (Abhängigkeitsliste, für `--changed` wiederverwenden), `docs/ENGINEERING.md`, `README.md` („Aufbau“), `docs/work-packages/README.md`, `CLAUDE.md` (Abschnitt „Arbeiten“).

Dieses Paket ändert keinen Produktivcode in `packages/` oder `app/`. Es ändert Prüfwerkzeuge und Doku.

## Inhalt

**Gate (`tool/gate.dart`)**
- **Kompakte Ausgabe als Standard.** `dart test` und `flutter test` laufen mit `--reporter=failures-only`. Die Ausgabe der Unterprozesse wird gepuffert, nicht mehr mit `inheritStdio` durchgereicht. Bei Erfolg erscheint pro Schritt nur eine Zeile. Bei einem Fehler erscheint die gepufferte Ausgabe dieses Schritts, auf sinnvolle Länge gekürzt (z. B. die letzten 200 Zeilen je Schritt mit Hinweis auf die Gesamtlänge), damit Analyse- und Testfehler vollständig lesbar bleiben.
- **Zusammenfassung am Ende**, eine Tabelle: Schritt, Ergebnis (ok/ROT/übersprungen), Dauer in Sekunden, bei Tests Anzahl und Abdeckung. Danach die Gesamtdauer und die Zeile `GATE GRÜN` bzw. `GATE ROT: <Schritte>`. Der Exit-Code bleibt wie bisher.
- **`--verbose`** stellt die bisherige Ausgabe her (Standard-Reporter, Durchreichen).
- **`--changed`**: ermittelt die betroffenen Pakete aus `git diff --name-only $(git merge-base main HEAD)` plus nicht committeten Änderungen (`git status --porcelain`) und prüft nur diese **plus alle Pakete, die von ihnen abhängen** (transitiv, aus den `pubspec.yaml`-Abhängigkeiten bzw. der Liste in `check_deps.dart`; z. B. Änderung in `wendelin_core` → alle Pakete, `evals` und die App). Regeln:
  - Änderungen unter `app/` → App-Schritte. Änderungen an `pubspec.yaml`/`pubspec.lock` im Root, `analysis_options.yaml` oder `tool/gate.dart` → alles.
  - Nur Doku (`docs/`, `*.md` außerhalb von Code-Ordnern) → nur die globalen Prüfungen (Secrets, Abhängigkeiten, Größen).
  - Format und Analyse laufen auf die betroffenen Ordner beschränkt.
  - Die Zusammenfassung nennt, welche Pakete warum geprüft wurden („wendelin_agent: geändert; wendelin_voice: hängt von wendelin_agent ab“).
  - `--changed` ist für schnelle Zwischenstände gedacht. Vor dem Commit bzw. Merge gilt weiter das volle Gate (bzw. der in `CLAUDE.md` festgelegte Umfang). Das steht im Hilfetext.
- Laufzeit je Schritt wird immer gemessen (auch mit `--verbose`).
- Hilfetext (`--help`) mit allen Schaltern.

**Größenregeln und Größen-Check**
- `docs/ENGINEERING.md` bekommt einen Abschnitt „Größen“ mit Richtwerten:
  - Produktivdatei: Ziel ≤ 400 Zeilen, **Warnung > 600, Fehler > 800**.
  - Testdatei: **Warnung > 1 000, Fehler > 1 500**.
  - Funktion bzw. `build()`: **Warnung > 80 Zeilen**, Fehler > 150. Klasse: Warnung > 400.
  - Review-Einheit: ca. 1 500 Zeilen geänderter Produktivcode (siehe unten).
  - Ausnahmen: generierter Code (`*.g.dart`, `*.steps.dart`, drift-Schemas unter `test/generated/`), Fixtures (`test/fixtures/`), `lib/testing/` (nur Warnung, nie Fehler). Kotlin (`*.kt`) gilt wie Dart.
- `tool/check_sizes.dart` (neu, reines Dart, < 1 s, im Gate als eigener Schritt):
  - Dateigrößen gegen die Schwellen. Funktions- und Klassenlängen über `package:analyzer` (bevorzugt, ist schon transitiv im Workspace) oder eine dokumentierte Klammer-Heuristik. Ist die Funktionsmessung zu teuer oder zu ungenau, nur Warnung.
  - **Allowlist** `tool/size_allowlist.yaml` für Bestandsdateien über der Fehlerschwelle: Pfad, aktuelle Zeilenzahl als Obergrenze, Verweis auf das R-Paket, das sie abbaut (z. B. `agent_runner.dart: 994 # WP37`). Eine Datei auf der Allowlist darf nicht über ihre Obergrenze wachsen. Unterschreitet sie die Fehlerschwelle, meldet der Check, dass der Eintrag zu entfernen ist (Fehler, damit die Liste nur schrumpft).
  - Warnungen erscheinen in der Gate-Zusammenfassung als Anzahl, mit `--verbose` als Liste.
  - `--report` gibt die Top 25 Dateien, die größten Klassen und die längsten Funktionen aus (Messwerte für R2–R6).
  - Tests für den Check (kleine Beispieldateien unter `tool/test/` oder Selbsttest wie bei `android_device.sh`).
- `docs/work-packages/README.md`: Hinweis zur maximalen Größe eines Arbeitspakets: Richtwert ca. 1 500 Zeilen geänderter Produktivcode je Review-Einheit, größere Pakete werden in Teil-Merges (a/b/c) mit eigenem Review geschnitten. Dazu die Liste der **Merge-Hotspots** aus dem Gutachten H2 (`wendelin_integrations.dart`, `fakes.dart`, `testing.dart`, `app/lib/main.dart`, `app.dart`, `di/providers.dart`, `di/integration_specs.dart`, `ui/routes.dart`, `test/support/test_env.dart`, `AndroidManifest.xml`, `app/pubspec.yaml`, `ui/screens/labels.dart`, `test/di/wiring_test.dart`) mit der Regel „nur anhängen, nicht umsortieren; bei Konflikt den Integrator fragen“. Die Liste wird nach WP38 gekürzt.

**Architekturkarte `docs/ARCHITECTURE.md`** (Richtwert ≤ 200 Zeilen, Verweis aus `CLAUDE.md` und `README.md`)
- **Wo liegt was:** je Paket zwei bis vier Zeilen mit Einstiegsdateien und wichtigsten Typen; `app/lib` nach Ordnern (`agent/`, `di/`, `platform/`, `ui/`, `voice/`, `debug/`), mit dem Hinweis auf die heutige Mischlage in `di/` (N7, H3) bis WP39.
- **Pakete und Abhängigkeiten** als Kurzfassung mit Verweis auf `ENGINEERING.md`.
- **Ports:** Tabelle aller Ports mit Fundort (`wendelin_integrations`, `wendelin_voice`, `wendelin_mcp/src/ports.dart`, `wendelin_agent/src/ports.dart`) und App-Implementierung in `app/lib/platform/`.
- **App-Verdrahtung:** Riverpod-Provider nach Bereich, Start (`main.dart`, `startup.dart`), Integrationsregistry (`integration_specs.dart`, `IntegrationActivator`, `UserIntegrationSync`), Overlay-Engine.
- **Datenfluss einer Anfrage** mit Datei je Station: Auslöser (Mikrofon, Power-Taste/Overlay, Text) → `VoiceController` → `AgentController` → Routing → `AgentRunner` → `ToolExecutor` → Integration → Port → `app/lib/platform` → Kotlin-Kanal, und zurück (Events, Reducer, Tool-Karte, Bestätigung, Undo, Audit).
- **Datenschutz und Taint:** wo Sensibilitätsstufen, Tool-Katalog je Zielstufe, Ausblenden geschützter Ergebnisse, Privatsphäre-Untergrenze und Eskalation umgesetzt sind (K9, K10).
- **Voice-Pipeline:** VAD → STT → Endpointing → Agent → Sprechtext → TTS, Modellkatalog und Download, geteiltes Whisper (ADR 0007, 0008).
- **Plattformkanäle:** Tabelle Kanalname → Dart-Datei → Kotlin-Datei.
- **HTTP-Stacks** (N3): Liste der vorhandenen Stacks mit Zweck und dem Hinweis, keinen neuen anzulegen.
- **Checklisten „Feature → Dateien“:** neue Integration, neue Einstellungsseite, neuer Kotlin-Kanal, neue Provider-Art. WP38–WP40 führen sie nach.

**Doku-Korrekturen**
- `ENGINEERING.md`, Repository-Layout: Liste der Integrationen vervollständigen (Listen, Obsidian, Bring!, HTTP-Tools, App-Erkennung u. a. nach Stand `main`). Die Ports-Regel lautet künftig: „Zugriff auf Gerätefunktionen nur über Ports. Ports liegen in dem Paket, das sie braucht (`ports.dart` bzw. `*_port.dart`), die Flutter-Implementierung in `app/lib/platform/`.“ Gate-Beschreibung um Zusammenfassung, `--changed`, `--verbose` und Größen-Check ergänzen.
- `README.md`, Abschnitt „Aufbau“: Zeile für `wendelin_mcp`, Integrationsliste aktualisieren, Verweis auf `docs/ARCHITECTURE.md`.
- Kurze `README.md` für `wendelin_core`, `wendelin_providers`, `wendelin_tools`, `wendelin_agent` (Zweck, Einstiegspunkte, wichtigste Typen, je ≤ 30 Zeilen).
- `CLAUDE.md`, Abschnitt „Arbeiten“: Gate-Aufruf für Agenten (kompakte Ausgabe ist Standard; `--changed` für Zwischenstände; App-Tests einzeln mit `flutter test test/<pfad>`), Goldens nur auf macOS aktualisieren, auf Linux `--exclude-tags golden` (N4). Höchstens fünf neue Zeilen.
- N5: bekannte plattformabhängige Tests (`app/test/platform/voice/ffi_support.dart`, `model_files_test.dart`) bekommen ein Tag `platform-sensitive`, in `dart_test.yaml` bzw. der App-Testkonfiguration erklärt. Sie laufen weiter im Gate.

## Abnahmekriterien
- [ ] Gate-Ausgabe kompakt: grüner Lauf `dart run tool/gate.dart --no-app` erzeugt ≤ 80 Zeilen (vorher 3 916 Zeilen / 434 KB). Ein absichtlich roter Test (lokal, nicht committet) erscheint mit Testname, Fehlermeldung und Datei in der Ausgabe, ebenso ein Analysefehler.
- [ ] Zusammenfassung mit Ergebnis und Dauer je Schritt, Gesamtdauer, `GATE GRÜN`/`GATE ROT: …`. Exit-Code bei Rot ≠ 0 (Test).
- [ ] `--verbose` liefert die bisherige Ausgabe.
- [ ] `--changed`: Tabellentest der Paketauswahl (reine Funktion von geänderten Pfaden auf Paketmenge): Änderung in `wendelin_core` → alle Pakete + App; in `wendelin_agent` → agent, voice, evals, App; nur `docs/` → nur globale Prüfungen; `tool/gate.dart` → alles. Die Ausgabe nennt den Grund je Paket.
- [ ] `tool/check_sizes.dart` im Gate, < 1 s Laufzeit, mit Tests. Allowlist enthält alle Bestandsdateien über der Fehlerschwelle, jede mit Verweis auf das abbauende R-Paket. Wachsen einer Allowlist-Datei und vergessenes Entfernen eines Eintrags werden als Fehler erkannt (Test).
- [ ] `--report` liefert Top-25-Dateien, größte Klassen und längste Funktionen. Werte von `main` als Ausgangsbasis im Abschlussbericht.
- [ ] `docs/ARCHITECTURE.md` mit allen oben genannten Abschnitten. Jeder genannte Pfad existiert (kleines Prüfskript oder Gate-Schritt, der Pfadangaben in `ARCHITECTURE.md` auflöst).
- [ ] `ENGINEERING.md` (Integrationsliste, Ports-Regel, Gate, Größen), `README.md` (Aufbau mit `wendelin_mcp`), `work-packages/README.md` (WP-Größe, Hotspots), `CLAUDE.md` (Gate-Aufruf, Goldens) angepasst. READMEs für core, providers, tools, agent vorhanden.
- [ ] Verhaltensneutral: kein Diff unter `packages/*/lib`, `app/lib`, `app/android`. Tests der Pakete und der App unverändert grün, Goldens unverändert.
- [ ] Gate grün (voll, mit App). Diff-Richtwert: Werkzeugcode ≤ 1 500 Zeilen.
- [ ] Messwerte im Abschlussbericht: Ausgabezeilen/-größe und Laufzeit des Gates vorher/nachher (`--no-app` und voll), Laufzeit `--changed` für eine Änderung nur in `wendelin_agent`.

Gerätetests: keine nötig. Die Selbsttests der Geräte-Skripte laufen weiter im Gate.
