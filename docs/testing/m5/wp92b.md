# WP92b Personen: Anrede, Gedächtnis, Agent

Voraussetzung: WP92a eingerichtet (Modell geladen, Schalter „Sprechererkennung“ an, mindestens zwei Personen eingelernt, z. B. Maintainer und eine zweite Stimme), zwei Provider-Profile (Standard und ein weiteres, z. B. Claude), Integration „Gedächtnis“ aktiv.

- [ ] **Personenliste**: Einstellungen → Sprache → Sprechererkennung. *Erwartet*: Unter „Personen“ stehen die eingelernten Personen; Antippen öffnet die Person (Anrede, Gedächtnis, Agent, Neu einlernen, Person löschen). Kein Papierkorb mehr in der Liste.
- [ ] **Anrede**: In der Person „Anrede“ setzen (z. B. „Maintainer“), leer lassen bei der zweiten. Sprachbefehl „Wie heiße ich?“ von beiden. *Erwartet*: Person 1 wird mit der Anrede angesprochen, Person 2 mit dem eingelernten Namen; ein Unbekannter oder Tippen im Chat bekommt die Anrede aus Einstellungen → Assistent (wie bisher).
- [ ] **Eigenes Gedächtnis**: Person 1: „Merk dir, ich mag Koriander.“ Person 2: „Was mag ich?“. *Erwartet*: Person 2 erfährt nichts davon; Person 1 sieht den Eintrag unter Person → „Einträge ansehen“, er fehlt in Einstellungen → Gedächtnis (Standard) und im Markdown-Export des Standards. Unbekannte Stimme: „Was mag Maintainer?“ findet nichts.
- [ ] **Standard-Gedächtnis**: Bei Person 2 den Schalter „Eigenes Gedächtnis“ ausschalten. *Erwartet*: Person 2 sieht und ändert die bisherigen Einträge des Standard-Gedächtnisses (ebenso Tippen und Unbekannte); Einträge von Person 1 bleiben für sie unsichtbar.
- [ ] **Undo**: Person 1 „Merk dir X“, in der Karte „Vergessen“. *Erwartet*: Nur der Eintrag von Person 1 verschwindet; „Wiederherstellen“ nach „Vergiss X“ legt ihn wieder im Gedächtnis der Person 1 an, nie im Standard.
- [ ] **Agent**: Bei Person 1 „Agent“ → anderes Profil wählen. *Erwartet*: Die Antwortzeile (Provider-Chip) zeigt das gewählte Profil, bei Unbekannten und Person 2 weiter den Standard. Einstellungen → Provider: der Standard bleibt unverändert. „Privat: …“ geht trotz Person-Agent an das Ziel der Regel; „Claude, …“ weiter an Claude.
- [ ] **Personenwechsel**: Person 1 stellt eine Frage mit Folgefrage, dann spricht Person 2 die Folgefrage. *Erwartet*: Hinweis „neue Unterhaltung“ (Sitzungsbeginn im Verlauf), keine Rückbezüge auf die Frage von Person 1, Agent und Gedächtnis von Person 2. Unbekannte Folgefrage (oder getippt) bleibt in der laufenden Unterhaltung bei Person 1.
- [ ] **Löschen**: Person mit eigenem Gedächtnis löschen. *Erwartet*: Dialog nennt die Anzahl der Einträge („… und 3 Einträgen im eigenen Gedächtnis“); danach sind Embeddings, Einstellungen und die Einträge weg, das Standard-Gedächtnis ist unverändert. Bei Person mit Standard-Gedächtnis nennt der Dialog keine Zahl. Datenschutz → „Alles löschen“ entfernt alle Personen samt deren Gedächtnis.
- [ ] **Nichts im Klartext**: `adb shell run-as <paket> ls -R files databases shared_prefs` zeigt keine Namen/Anreden; Prüfprotokoll, Audit-Export und Logcat enthalten weder Personenname, Anrede, Personen-Id (`p:…`) noch Embeddings. Die Datenbank trägt nur den Namespace-Schlüssel `p:<id>` an Gedächtniseinträgen (nicht exportiert; Markdown-Export ohne Schlüssel).
- [ ] **Unbekannt = heute**: Schalter „Sprechererkennung“ aus oder Fremdstimme. *Erwartet*: Prompt, Agent und Gedächtnis exakt wie vor WP92b (Standard-Namespace, Standard-Agent, Anrede aus „Assistent“).

## E2E (Emulator, synthetisches Audio)

`app/integration_test/speaker_persons_e2e_test.dart`: Zwei synthetische Sprecher (Thorsten/Kerstin) werden mit dem echten CAM++-Modell eingelernt. Dann laufen Anfragen über den echten Agent-Controller mit Fake-Providern: je Person Anrede, eigenes Gedächtnis und eigener Agent; eine andere Person startet eine neue Unterhaltung; die Fremdstimme bleibt unbekannt und bekommt den Standard; Löschen einer Person bzw. „Alles löschen“ entfernt Namespace, Einstellungen und Embeddings. Echte STT/Pipeline deckt der Test nicht ab (Unit-Tests). Assets wie bei WP92a; `tool/e2e_android.sh` deinstalliert die App am Ende, deshalb vor jedem Lauf neu installieren und das prepare-Skript aus dem Handoff-Ordner aufrufen.

```sh
adb -s emulator-5554 install -r app/build/app/outputs/flutter-apk/app-debug.apk
~/ai/james-wt/handoff/wp92a-e2e/prepare.sh emulator-5554
WENDELIN_WP92A_DIR=wp92a tool/e2e_android.sh integration_test/speaker_persons_e2e_test.dart
```

Ergebnis 2026-10-19: alle Szenarien grün (Thorsten 0,904, Kerstin 0,789, Fremdstimme 0,284 → unbekannt; nach dem Löschen Thorsten 0,094 → unbekannt).
