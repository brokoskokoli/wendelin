# Testprotokoll (laufende Testrunde)

Eine Datei für die aktuelle Testrunde am Gerät. Die Prüfpunkte selbst stehen in den Anleitungen unter `m5/`; hier steht nur, was mit welchem Release-Kandidaten in welcher Reihenfolge zu prüfen ist, und das Ergebnis je Block.

Regeln: Öffentliches Repo. Ergebnisse ohne Namen, Kontaktdaten, Geräte-Seriennummern, echte Geräte- oder Raumnamen und ohne Transkripte; Logzeilen nur gekürzt auf die Diagnosefelder. Ergebnis je Block: `ok`, `Befund: …` (kurz, mit Prüfpunkt-ID) oder `offen`.

## Aktueller Stand

- Release-Kandidat: **v0.1.9-rc1** (GitHub-Release, Vorabversion), Commit siehe Release-Seite. APK und `SHA256SUMS` von der Release-Seite laden; Zertifikat-Fingerabdruck wie im README.
- Installation über v0.1.8 (gleiche Signatur, Daten bleiben).

## Reihenfolge und Ergebnisse

### Neu in v0.1.9-rc1

| Block | Anleitung | Ergebnis |
| --- | --- | --- |
| Gleicher Fehlaufruf wird nicht wiederholt | [m5/wp200.md](m5/wp200.md) | offen |
| MCP „Ohne Nachfrage“ nach Inhalten desselben Servers | [m5/wp201.md](m5/wp201.md) | offen |

### Neu in v0.1.8-rc3

| Block | Anleitung | Ergebnis |
| --- | --- | --- |
| Bestätigungs- und Stopp-Ton still in der Ruhezeit der Station | [m5/wp197.md](m5/wp197.md) | offen |
| Overlay: „Ich höre zu“ statt „Moment …“, sobald Ton ankommt | [m5/wp198.md](m5/wp198.md) | offen |

### Neu in v0.1.8-rc2

| Block | Anleitung | Ergebnis |
| --- | --- | --- |
| Mikrofon zuerst, „Ich höre zu“ ab dem ersten Ton | [m5/wp194.md](m5/wp194.md) | offen |
| Nichts gehört: nach 5 s still mit Stopp-Ton | [m5/wp195.md](m5/wp195.md) | offen |
| Langes Transkript kleiner | [m5/wp196.md](m5/wp196.md) | offen |

### Neu in v0.1.8-rc1

| Block | Anleitung | Ergebnis |
| --- | --- | --- |
| Hinweisbegriffe: Listen und Home Assistant vor Kontakten, Gerätesynonyme | [m5/wp191.md](m5/wp191.md) | offen |
| Push-to-Talk durch Halten des Mikrofon-Buttons | [m5/wp192.md](m5/wp192.md) | offen |

### Neu in v0.1.1-rc1

| Block | Anleitung | Ergebnis |
| --- | --- | --- |
| Einrichtungsassistent (Update-Fall und frische Installation) | [m5/wp174.md](m5/wp174.md) | offen |
| Einstellungen neu geordnet, Aktivierungswort braucht das Modell | [m5/wp173.md](m5/wp173.md) | offen |
| Weckwort: Prüfer B, Rückfall, Hinweis bei fehlendem Modell, Station | [m5/wp171.md](m5/wp171.md) | offen |
| Overlay schließt nach dem Zuhören, Weckwort danach wieder bereit | [m5/wp172.md](m5/wp172.md) | offen |

### Aus v0.1.0 (rc11–rc13), noch offen

| Block | Anleitung | Ergebnis |
| --- | --- | --- |
| Spotify: auf dem spielenden Gerät weiter (Chromecast), C1–C5 | [m5/wp166.md](m5/wp166.md) | offen |
| Kein Kommunikationsmodus mehr (Lautstärke gleichbleibend) | [m5/wp165.md](m5/wp165.md) | offen |
| Stufe je Geräteart, Sprechererkennung inkl. (d) fremde Person | [m5/wp160.md](m5/wp160.md) | offen |
| Gesperrt: Anfrage/Antwort im Overlay, Navigation nach Entsperren | [m5/wp163.md](m5/wp163.md) | offen |
| Kontakt-Felder, Waze, Navigation zum Kontakt | [m5/wp164.md](m5/wp164.md) | offen |
| Spotify auf dem Handy (ohne C2) | [m5/wp161.md](m5/wp161.md) | offen |
| Stationskanal, Mikrofonstart | [m5/wp158.md](m5/wp158.md) | offen |
| GPU-Prüfung nur mit Nachweis, „Eingeschränkte Einstellungen“ | [m5/wp159.md](m5/wp159.md) | offen |
| Lizenzen der Sprachmodelle | [m5/wp162.md](m5/wp162.md) | offen |

### Ältere Blöcke, noch offen

| Block | Anleitung | Ergebnis |
| --- | --- | --- |
| Entsperren und weitermachen | [m5/wp153.md](m5/wp153.md) | offen |
| Sitzungssperre und Abfluss-Schutz | [m5/wp157.md](m5/wp157.md) | offen |
| Weckwort-Archiv im Entwicklermodus | [m5/wp155.md](m5/wp155.md) | offen |
| „Hey Wendelin“ in Texten | [m5/wp156.md](m5/wp156.md) | offen |
| Sicherheitsstufe je Tool und Home-Assistant-Gerät | [m5/wp154.md](m5/wp154.md) | offen |
| Unterbrechen mit Weckwort (ohne Gesprächston-Punkte) | [m5/wp151.md](m5/wp151.md) | offen |
| Home Assistant: Zahl als Text, Wiederholungsabbruch | [m5/wp150.md](m5/wp150.md) | offen |
| Wake-Übergabe ohne Audiolücke | [m5/wp149.md](m5/wp149.md) | offen |
| Entwicklermodus | [m5/wp148.md](m5/wp148.md) | offen |

## Befunde

(Neue Befunde hier kurz eintragen: Datum, Block, Prüfpunkt, was passiert ist, was erwartet war. Der Orchestrator macht daraus Pakete.)
