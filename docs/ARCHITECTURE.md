# Architekturkarte

Wo liegt was, und welche Dateien gehören zu einer Änderung? Das ist nur der Index: Lies **nur den Bereich, den du brauchst**, nicht alle Dateien. Regeln und Abhängigkeiten stehen in `docs/ENGINEERING.md`, Entscheidungen in `docs/adr/`. Alle Pfadangaben und Links prüft `tool/check_docs.dart` im Gate. Wer Dateien verschiebt, führt den passenden Bereich nach.

## Bereiche

- **Pakete** (`packages/`, reines Dart): Einstiegsdateien und wichtige Typen je Paket. [packages.md](architecture/packages.md); Abhängigkeiten je Paket erzeugt: [generated/packages.md](architecture/generated/packages.md).
- **App** (`app/lib`): Ordner und ihre Aufgaben, die vier Einstiege. [app.md](architecture/app.md)
- **Ports**: wo ein Port liegt und wer ihn in der App umsetzt. [ports.md](architecture/ports.md)
- **App-Verdrahtung**: Start, Provider, Integrationsregistry, Overlay-Engine, Wake-Word-Dienst. [wiring.md](architecture/wiring.md)
- **Integrationen**: erzeugte Liste aus der Registry in [generated/integrations.md](architecture/generated/integrations.md); nicht ableitbare Angaben je Integration in einer eigenen Datei [integrations/](architecture/integrations/README.md) (`<id>.md`, keine gemeinsame Tabelle).
- **Datenfluss einer Anfrage**: Weg von Eingabe bis Antwort. [dataflow.md](architecture/dataflow.md)
- **TEE-Anbieter** (WP52, ADR 0014): Attestierung in der App. [tee.md](architecture/tee.md)
- **Datenschutz und Taint** (K9, K10). [privacy.md](architecture/privacy.md)
- **Voice-Pipeline** (ADR 0007, 0008). [voice.md](architecture/voice.md)
- **Plattformkanäle**: Kotlin-Kanäle und ihre Dart-Seite. [channels.md](architecture/channels.md)
- **HTTP-Stacks** (N3). [http.md](architecture/http.md)
- **Release und Signatur** (WP131): Schlüssel, Secrets, Tag-Release, Umstieg vom Debug-Schlüssel. [RELEASE.md](RELEASE.md)
- **Checklisten „Feature → Dateien“**: neue Integration, Einstellungsseite, Kanal u. a. [checklists.md](architecture/checklists.md)

Gerätetests je Arbeitspaket stehen in `docs/testing/m5/README.md` (erzeugter Index).
