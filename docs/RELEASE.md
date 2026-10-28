# Release und Signatur

Release-APKs werden mit einem eigenen Schlüssel signiert (K102, K103). Der Schlüssel liegt nie im Repo. GitHub baut bei einem Tag `v*` die signierte APK und legt sie im Release ab (`.github/workflows/release.yml`, Prüfungen in `tool/release_check.sh`).

## 1. Schlüssel erzeugen (einmalig)

```bash
keytool -genkeypair -v -keystore ~/wendelin-release/wendelin-release.jks \
  -alias wendelin -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=Wendelin"
```

- `-validity 10000` sind etwa 27 Jahre (Pflicht: mindestens 25).
- `keytool` fragt Store- und Schlüsselpasswort ab (lang, zufällig, aus dem Passwortmanager). Der Name im Zertifikat (`-dname`) ist öffentlich sichtbar: nichts Persönliches eintragen.
- Dateirechte: `chmod 600`, Ordner nicht in Cloud-Sync oder Backup-Ordner mit Fremdzugriff.

## 2. Sichern

Geht der Schlüssel verloren, kann keine installierte Version mehr aktualisiert werden (Deinstallation und Datenverlust).

- Keystore **und** beide Passwörter im Passwortmanager (Datei als Anhang) und zusätzlich an einem zweiten Ort (verschlüsselter USB-Stick oder zweiter Rechner).
- Nach dem Sichern prüfen, dass die Kopie lesbar ist: `keytool -list -keystore <kopie>`.

## 3. Fingerabdruck

```bash
keytool -list -v -keystore ~/wendelin-release/wendelin-release.jks -alias wendelin | grep SHA256
```

Der SHA-256-Fingerabdruck des Zertifikats ist öffentlich. Er gehört in Googles Entwickler-Verifizierung (Konto des Maintainers: Fingerabdruck dort hochladen) und steht bei jedem Release in den Notizen und im Step-Summary des Workflows.

## 4. Einrichtung auf GitHub (Environment „release“)

Die Secrets liegen nicht im Repo, sondern in der Environment `release`. Deren Deployment-Regeln erlauben nur den Branch `main` und Tags `v*`; der Job `build` (er allein hat Zugriff auf die Secrets) läuft dadurch weder auf einem beliebigen Branch noch per `workflow_dispatch` auf einem Feature-Branch. Ein manueller Probelauf geht nur auf `main`.

```bash
REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"   # {owner}/{repo}

# Environment mit eigenen Branch-/Tag-Regeln anlegen
gh api -X PUT "repos/$REPO/environments/release" \
  -F 'deployment_branch_policy[protected_branches]=false' \
  -F 'deployment_branch_policy[custom_branch_policies]=true'
gh api -X POST "repos/$REPO/environments/release/deployment-branch-policies" -f name=main -f type=branch
gh api -X POST "repos/$REPO/environments/release/deployment-branch-policies" -f name='v*' -f type=tag

# Secrets in die Environment (Keystore per Pipe, nie per echo; Passwörter werden abgefragt)
base64 -i ~/wendelin-release/wendelin-release.jks | gh secret set ANDROID_KEYSTORE_BASE64 --env release
gh secret set ANDROID_KEYSTORE_PASSWORD --env release
gh secret set ANDROID_KEY_PASSWORD --env release

# Alias ist kein Geheimnis: Repo-Variable
gh variable set ANDROID_KEY_ALIAS --body wendelin

# Alte Repo-Secrets (falls vorhanden) löschen, sonst wären sie für alle Workflows lesbar
gh secret delete ANDROID_KEYSTORE_BASE64
gh secret delete ANDROID_KEYSTORE_PASSWORD
gh secret delete ANDROID_KEY_PASSWORD
```

Prüfen: `gh api "repos/$REPO/environments/release/deployment-branch-policies" --jq '.branch_policies[] | [.name,.type]'` zeigt `main` und `v*`; `gh secret list --env release` nennt drei Secrets, `gh secret list` keine.

Der Alias als Repo-Variable: Als Secret würde GitHub „wendelin“ überall im Log maskieren und Job-Outputs mit dem APK-Namen verwerfen.

Empfehlung zusätzlich: Tags `v*` per Tag-Schutzregel (Settings → Rules) auf den Maintainer beschränken, weil jeder mit Schreibrecht sonst einen Release-Lauf auslösen kann (die Secrets bekommt der Lauf trotzdem nur für `main`/`v*`).

## 5. Release per Tag

1. `version:` in `app/pubspec.yaml` anheben (`0.6.0+7`; der Teil nach `+` ist der `versionCode` und muss bei jedem Release steigen), auf main mergen, Gate abwarten.
2. `git tag v0.6.0 && git push origin v0.6.0`. Der Tag ohne `-` ist ein reguläres Release und nur erlaubt, wenn der Commit auf `main` liegt; mit `-` (z. B. `v0.6.0-rc1`) ist es eine Vorabversion, die auch von einem Branch kommen darf (Probe).
3. Der Workflow bricht ab (rot, mit Meldung ohne Werte), wenn: Secrets fehlen, die Tag-Basisversion nicht der pubspec-Version entspricht, das Gate für den Commit nicht grün war, ein echtes Release nicht von `main` kommt, `check_apk.sh` rot ist oder das APK-Zertifikat nicht das des Keystores ist (z. B. Debug-Schlüssel).
4. Ergebnis: Release mit `wendelin-<version>.apk` und `SHA256SUMS`, Notizen aus den Merges auf main seit dem letzten echten Release-Tag.

Probeläufe: Actions → release → Run workflow (nur auf `main`; nur Build und Prüfungen, kein Release; die APK hängt 3 Tage als Artefakt am Lauf). Mit `probe_missing_secrets` bleiben die Secrets leer, der Lauf muss am Schritt „Secrets prüfen“ rot werden. Ein Test-Tag wie `v0.0.0-test` braucht eine passende pubspec-Version; danach Release und Tag löschen (`gh release delete v0.0.0-test --cleanup-tag`).

## 6. Lokal mit demselben Schlüssel signieren

`key.properties` in `app/android/` (gitignored) nach dem Muster `app/android/key.properties.example` anlegen (`storeFile` absolut, `storePassword`, `keyAlias`, `keyPassword`) oder die vier Umgebungsvariablen `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` setzen. Dann `cd app && flutter build apk --release`.

- Ohne beides warnt der Build und nimmt den Debug-Schlüssel (nur für lokale Tests, nie weitergeben).
- Unvollständige Angaben oder eine fehlende Keystore-Datei brechen immer ab.
- `WENDELIN_REQUIRE_RELEASE_SIGNING=1` bricht auch ab, wenn gar nichts gesetzt ist (so baut der Workflow; absichtlich nicht `CI=true`, weil das Gate-Job `apk` ohne Schlüssel baut).
- Prüfen: `apksigner verify --print-certs app/build/app/outputs/flutter-apk/app-release.apk` zeigt den Release-Fingerabdruck.

### Release-Kandidaten

Ein Release-Kandidat heißt `v<pubspec-version>-rcN` (z. B. `v0.6.0-rc1`, ohne Punkt vor `N`) und ist ein Tag auf `main`. Ablauf (Project Supervisor):

1. Auf genau dem Commit, der getaggt wird, ist das Gate grün (Abschnitt 5, Punkt 3 bricht sonst ab).
2. Tag setzen und pushen: `git tag v<version>-rcN && git push origin v<version>-rcN`. Zwischen Tag und dem Rest der Kette kommt kein Commit auf `main`.
3. `release.yml` baut die signierte Vorabversion (Abschnitt 5).
4. Herunterladen: `gh release download v<version>-rcN -R <owner>/<repo>` in ein leeres Verzeichnis, dann `shasum -c SHA256SUMS`.
5. APK und `VERSION.txt` (Commit-SHA, Version) in den Testordner des Maintainers legen.

Nach einem echten Release zuerst die pubspec-Version erhöhen: `vX-rcN` sortiert vor `vX`, ein Kandidat zur bereits veröffentlichten Version wäre also älter als das Release.

## 7. Umstieg vom Debug-Schlüssel auf dem Handy

Android lässt kein Update über eine APK mit anderem Schlüssel zu. Einmalig: Daten sichern, deinstallieren, neue APK installieren, Daten zurückspielen. Am besten zusammen mit dem großen Gesamttest.

Die App erlaubt kein System-Backup (`allowBackup="false"`). Es gibt **keinen Gesamtexport**; die Datensicherung ist heute nur teilweise möglich:

| Daten | Sicherung | Wiederherstellung |
| --- | --- | --- |
| Routing-Regeln | Einstellungen → Routing → Export (JSON) | Import mit Vorschau |
| MCP-Server | Einstellungen → MCP → Export (ohne Tokens und Passwörter) | Import, Tokens neu eingeben |
| HTTP-Tools | Einstellungen → HTTP-Tools → Export (ohne Secrets) | Import, Secrets neu eingeben, „Ohne Nachfrage“ ist danach aus |
| Gedächtnis | Einstellungen → Gedächtnis → Export als Markdown | kein Import: Einträge per Hand oder per Sprache neu anlegen |
| Prüf- und Audit-Protokoll | JSON-Export (ohne Inhalte) | nur zum Ansehen, nicht wiederherstellbar |
| Einstellungen (Sprache, Stimme, Wake-Word-Empfindlichkeit u. a.) | **kein Export** | neu einstellen |
| Provider und API-Keys, OAuth-Anmeldungen | **kein Export** (Keys liegen nur im sicheren Speicher, nie in Exporten) | neu einrichten, bei Diensten neu anmelden |
| Verläufe (Unterhaltungen) | **kein Export** | gehen verloren |
| Wake-Vorlagen, Sprecherprofile (Personen) | **kein Export** | neu aufnehmen |

Ablauf:

1. Vor dem Umstieg alle Exporte der Tabelle ausführen und auf den Rechner kopieren. Provider, Keys und Einstellungen von der App-Anzeige abschreiben bzw. aus dem Passwortmanager bereithalten.
2. `adb uninstall app.wendelin` oder in den Android-Einstellungen deinstallieren.
3. Die APK aus dem Release (oder lokal mit Release-Schlüssel gebaut) installieren; Fingerabdruck mit `apksigner verify --print-certs` gegen den veröffentlichten Wert prüfen und die Prüfsumme gegen `SHA256SUMS`.
4. Provider einrichten, Exporte importieren, Wake-Word und Sprecherprofile neu aufnehmen.

Danach genügt jedes weitere Update über die APK desselben Schlüssels.

## 8. Modell-Dateien als Release

Eigene Modelle, z. B. das Wake-Word-Modell, liegen als eigene Releases `models-<art>-<stand>` (etwa `models-wake-v8a-clean`) mit `--latest=false`. Sie enthalten nur die Modelldatei und `SHA256SUMS`, keine Begleitdateien aus dem Training. Der Katalog der App (`packages/wendelin_voice/lib/src/models/`) zeigt auf die Download-URL und prüft die SHA-256. Neue Modelle bekommen ein neues Release, ein bestehendes wird nicht überschrieben.

```bash
gh release create models-wake-<stand> <modell>.onnx SHA256SUMS --target main --latest=false \
  --title "Wake-Word-Modell <stand>" --notes "…"
```
