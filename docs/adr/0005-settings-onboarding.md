# ADR 0005 – Einstellungen und Onboarding (`app/lib/ui/settings/`, `app/lib/ui/onboarding/`)

Status: vorgeschlagen · 2026-10-13

## Kontext
WP09 ersetzt die vorläufige Einstellungsseite aus WP08 und ergänzt Provider-Einrichtung, Listen (K6) mit Dateizugriff, Web-Suche, Gedächtnis, Datenschutz, Kosten, Assistent und das Onboarding. Mehrere Punkte lassen Konzept und Arbeitspaket offen.

## Entscheidungen

### 1. Einstellungen als Riverpod-Notifier über `SettingsRepository`
Laufzeit-Einstellungen (Tool-Schalter und Bestätigungen, Mindeststufe für sensible Integrationen, Web-Suche, Listen, Assistent, Aufbewahrung, Sprache, Onboarding) sind je ein Notifier in `app/lib/di/preferences.dart`. Sie starten mit den beim Start gelesenen Werten (`StartupSettings`) und speichern jede Änderung. Registry und `RiskPolicy` hören auf `toolPrefsProvider`; Web-Suche und Listen fließen über `IntegrationDeps` in die Integrationen. Profile und Eskalationskette verwaltet `profilesProvider`; jede Änderung invalidiert `storedProviderConfigProvider`.

### 2. API-Keys nie im App-Zustand; Dialog in zwei Prüfschritten
Der Key steht nur im Eingabefeld des Dialogs. Beim „Verbindung testen“ geht er direkt in den `SecretStore` (`provider.<profilId>.apiKey`), das Feld wird geleert, und der Adapter liest ihn von dort (`SecretReader`). Dieser erste Schritt lädt nur die Modelle (`listModels`), braucht also noch kein Modell. Erst „Modell prüfen“ ruft `test()` mit dem **gewählten** Modell auf; daraus kommen die geprüften Fähigkeiten. Vorlagen ohne Modellvorschlag (Ollama, eigener Endpunkt, OpenRouter, Tinfoil) scheitern deshalb nicht an einem Platzhalter-Modell. Wird der Dialog ohne Speichern verlassen, löscht `ProviderSetupSession.discard` den Key wieder.
Bestehende Profile öffnen denselben Dialog (gleiche Id, Felder vorbelegt). Ein neuer Key bekommt eine eigene Referenz: Abbrechen lässt den alten Key unangetastet, beim Speichern wird der ersetzte gelöscht. Beim Start entfernt `removeOrphanProviderSecrets` `provider.*`-Keys, auf die kein Profil verweist. Beim Löschen eines Profils werden alle `secretRefs` mitgelöscht. Web-Suche: Der Key liegt unter `web.search.<dienst>.apiKey`, das Backend liest ihn bei jeder Suche (`StoredKeyWebSearch`). Ein Test prüft die SQLite-Datei Byte für Byte auf den Key.

### 3. Eigener SAF-Kanal statt Plugin
`SafListFilePort` und `DocumentPicker` sprechen über `app.wendelin/files` mit `FilesChannel.kt`: `ACTION_OPEN_DOCUMENT`/`ACTION_CREATE_DOCUMENT`, `takePersistableUriPermission`, Schreiben mit Modus `wt`, rohe Bytes über den Kanal. UTF-8 wird in Dart dekodiert, ein BOM bleibt dabei erhalten (`decodeUtf8KeepingBom`, `utf8.decode` würde ihn entfernen). Jeder Aufruf hat ein Zeitlimit von 5 s, danach kommt `PortException(unavailable)`. Gründe: kein zusätzliches Plugin (K7), volle Kontrolle über Bytes und Fehlercodes, gleiches Muster wie der Kalender-Kanal (ADR 0004). Geprüft mit `listFilePortContract` gegen eine Kanal-Attrappe.

### 4. Listen auf dem Gerät
`exists` meldet einen verlorenen Zugriff als `permissionDenied` und nicht als „gibt es nicht“. Beim Start prüft `StartGate` die gespeicherten Berechtigungen (`hasAccess`). Fehlt eine, steht die Listen-Integration auf Fehler „Datei neu auswählen: …“, und die Liste ist in den Einstellungen markiert. Berechtigungen für Dateien, die nach einem Dateiwechsel oder einem verworfenen Dialog keine Liste mehr nutzt, werden freigegeben. Gelesen werden höchstens 5 MB. Fehlt auf dem Gerät eine Dateiauswahl, kommt „nicht unterstützt“ statt eines Absturzes.

`PlatformPorts.device` hat jetzt immer einen Listen-Port, die Definitionen kommen aus `listDefinitionsProvider`. Wer die erste Liste anlegt, schaltet die Integration damit ein. Danach prüft die Registry den Einrichtungsschritt neu. Beim Löschen der letzten Liste mit dieser Datei wird die URI-Berechtigung freigegeben.

### 5. Risikostufen nur verschärfen, „sensibel“ umschaltbar
Pro Tool gibt es zwei Einstellungen: aus/an (das Tool geht nicht ans Modell) und „Immer nachfragen“ für `read`/`write`-Tools (`RiskPolicy.setOverride(confirm)`). `external` fragt immer; es gibt keinen Weg, eine Stufe zu lockern (K8 b). Ob eine Integration als „sensibel“ gilt, stellt der Nutzer je Integration um (Standard: Wert der Integration). Die App kapselt die Integration dafür in `SensitivityOverride`, core bleibt unverändert.

### 6. Onboarding vor dem Hauptbildschirm
`StartGate` zeigt das Onboarding, solange `onboarding.done` nicht gesetzt ist (im Demo-Modus nie). Die Schritte sind Sprache (nur gespeichert, die Oberfläche bleibt vorerst deutsch), erster Provider (derselbe Dialog wie in den Einstellungen) und Integrationen (dieselben Schalter mit Erklärung vor der Berechtigung). Jeder Schritt lässt sich überspringen. Whisper-Download und Standard-Assistent sind ausgeblendet (M2).

### 7. Export über das Teilen-Menü
Die Exporte (Gedächtnis als Markdown, Prüfprotokoll als JSON) gehen über `share_plus` als Datei ins Teilen-Menü. Das Plugin bringt keine GMS-Abhängigkeit mit. Der Exporter ist austauschbar (`exporterProvider`).

### 8. Aufbewahrung
Beim Start und bei jeder Änderung der Aufbewahrung werden Prüfprotokoll **und** Gesprächsverläufe gelöscht, die älter als die gewählte Zahl Tage sind (Standard 30). „Alles löschen“ entfernt Verläufe und Protokoll. Gedächtnis und Einstellungen bleiben.

## Folgen
- Gerätetests für SAF und Dateiauswahl folgen in WP11.
- Neue Einstellungen bekommen einen Notifier in `preferences.dart` und ein Feld in `StartupSettings`.
