# WP169 – GitHub-Repo auf den Stand von v0.1.0: Lizenz, README (en/de), Screenshots, Homepage

**Zuordnung:** Wunsch des Maintainers vom 2026-10-28 nach dem ersten Release v0.1.0: „GitHub aktualisieren, README schön machen, vor allem den Inhalt auf den aktuellen Stand bringen.“

## Entscheidungen Maintainer (2026-10-28)
- Lizenz **GPL-3.0-or-later**. Copyright-Inhaber ohne Klarnamen (Login bzw. „Wendelin contributors“). CONTRIBUTING.md mit dem Hinweis, dass Beiträge vom Maintainer auch unter anderen Lizenzen genutzt werden dürfen (Doppellizenz bleibt möglich).
- README **englisch** (`README.md`) plus **`README.de.md`**, Sprachumschalter oben. Die übrige Doku bleibt deutsch.
- Dazu: Repo-Einstellungen (Beschreibung, Topics, Homepage-Link; Wiki aus, Discussions an – nur vorbereiten, setzen tut der Orchestrator nach Freigabe), **Screenshots** und **Homepage auf GitHub Pages** (en + `/de/`).

## Stand heute
- Kein `LICENSE`, keine Topics, keine Homepage, Wiki an. README deutsch, Stand M1–M3 (Demo-Anleitungen, „Lizenzseite fehlt noch“), nennt viele heutige Funktionen nicht.
- Release-Workflow `.github/workflows/release.yml` (Tag `v*`, Notizen aus Merges; v0.1.0 hat von Hand zusammengefasste Notizen), Release-Doku `docs/RELEASE.md`.
- Funktionsumfang v0.1.0 (Quelle der Wahrheit: Gesamtkonzept, STATUS, Release-Notizen v0.1.0): Standard-Assistent mit Overlay, „Hey Wendelin“ lokal, Whisper/Parakeet lokal, Sprachausgabe lokal, Gesprächsmodus mit Unterbrechen; LLM-Anbieter nach Wahl mit TEE-/GPU-Attestierung; Home Assistant, Spotify, Medien, Kontakte, Anrufe/SMS, Maps/Waze, Wecker, Obsidian, MCP/HTTP; Sicherheitsstufen A–D und Verhalten gesperrt; Stationsmodus; Spracherkennung für andere Apps; ohne Google Play; de/en/fr.

## Inhalt
- **Teil A (Lizenz):** `LICENSE` (voller GPL-3.0-Text), Lizenzangaben für Drittteile (Schriften OFL, Sprachmodelle: Verweis auf die Lizenzseite in der App aus WP162 bzw. die vorhandenen Herkunftsangaben). SPDX/REUSE: mindestens `REUSE.toml` mit pauschaler Zuordnung; Kopfzeilen in jeder Quelldatei nur, wenn billig und ohne Konflikt mit Gate-Checks (`check_sizes`, Format). `pubspec.yaml`-Felder bzw. Android-Metadaten prüfen. GitHub muss die Lizenz erkennen.
- **Teil B (README en/de):** Aufbau nach Skill `github-repo-setup` (`~/.claude/skills/github-repo-setup/references/repo-files.md`, Vorlagen in `templates/`): Badges (CI, Release, Lizenz, Android), Pitch, Screenshot, Download-Knopf auf `releases/latest`, „Why Wendelin?“, Funktionen, Installation (APK, Zertifikat-Fingerabdruck prüfen, „Eingeschränkte Einstellungen“), erste Schritte (Anbieter einrichten), Datenschutz (was lokal bleibt, welche Verbindungen es gibt), aus dem Quellcode bauen (kurz, Verweis auf `docs/ENGINEERING.md`), Mitmachen, Lizenz, Danksagungen. Alte Demo-Anleitungen M1–M3 nach `docs/` verschieben oder streichen, wenn überholt.
- **Teil C (Screenshots):** reproduzierbar auf dem Emulator (`tool/e2e_android.sh`/Integrationstest oder Skript), nur synthetische Daten (keine echten Namen, Kontakte, Geräte, Pfade), hell/dunkel, englische Oberfläche fürs README; als WebP/PNG unter `docs/images/` bzw. `website/images/`. Skript und Ablauf dokumentieren.
- **Teil D (Homepage):** `website/` statisch (en unter `/`, de unter `/de/`, `privacy.html` je Sprache mit allen Netzverbindungen der App), SEO (Title, Description, Canonical, OG mit Social Image, JSON-LD, `sitemap.xml` mit hreflang, `robots.txt`, Favicon aus dem App-Icon), Deploy `.github/workflows/pages.yml` aus der Skill-Vorlage (Fork-Schutz). Social-Preview-Bild 1280×640 rendern (Hochladen macht der Maintainer).
- **Teil E (Repo-Einstellungen vorbereiten):** Vorschlag für Beschreibung (en, ≤ 350 Zeichen), 10–20 Topics, Homepage-URL, Wiki aus, Discussions an – als Liste in der Fertigmeldung; nicht selbst setzen.

## Datenschutz und Grenzen
- Öffentliches Repo: kein Name, keine Kontaktdaten, keine Anwesenheit des Maintainers, keine absoluten Pfade (`check_privacy`, Liste verbotener Begriffe außerhalb des Repos). Kein Impressum, keine Anschrift oder E-Mail.
- Zur Herkunft der Trainingsdaten des Weckwort-Modells nichts schreiben, was über die vorhandene Doku hinausgeht; Modellvarianten nur neutral benennen.
- Nicht dazu: Homebrew/winget, Promotion, Änderungen am Release-Workflow (außer ein Verweis auf CHANGELOG ist billig und wird abgestimmt).

## Abnahmekriterien
- [ ] `LICENSE` vorhanden, GitHub-Lizenzerkennung lokal plausibel (Lizenztext unverändert), Drittlizenzen benannt.
- [ ] `README.md` und `README.de.md` inhaltlich gleich, aktuell (gegen Konzept/STATUS geprüft), Links funktionieren (Linkprüfung), Bilder vorhanden.
- [ ] Screenshots reproduzierbar per Skript, nur synthetische Daten (Review prüft jedes Bild).
- [ ] `website/` besteht SEO-Checkliste aus `references/website.md`, `pages.yml` mit Fork-Schutz.
- [ ] `--changed` grün, CI grün, Review FREIGABE (Schwerpunkt Datenschutz, Richtigkeit der Funktionsbeschreibung).

## Parallel-Hinweise
- Läuft allein. Emulator für Teil C: Zuteilung beim Orchestrator.
