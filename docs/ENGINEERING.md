# Engineering-Regeln (Wendelin)

Verbindlich für alle Beiträge, auch für Coding- und Review-Agenten. Fachliche Grundlage: `../Voice Agent App – Gesamtkonzept.md`, Design: `design/DESIGN.md`.

## Repository-Layout

```
pubspec.yaml                 # Dart-Pub-Workspace (eine pubspec.lock für alles)
analysis_options.yaml        # strenge Lints, gilt für alle Pakete
packages/
  wendelin_core/             # reines Dart: Nachrichtenformat, Interfaces, Events, Fehler, SSE-Parser. KEINE Abhängigkeiten außer meta/collection
  wendelin_providers/        # reines Dart: LLM-Adapter (Anthropic, OpenAI-kompatibel), SSE, Modellkatalog, Kosten
  wendelin_tools/            # reines Dart: ToolRegistry, ToolExecutor, Risiko, Argumentprüfung, Undo
  wendelin_agent/            # reines Dart: Agent-Schleife, Kontextaufbau, Limits, Eskalation
  wendelin_storage/          # reines Dart + drift: Datenbank, Repositories, SecretStore-Interface
  wendelin_integrations/     # reines Dart: eingebaute Integrationen über Ports (Kalender, Zwischenablage, Wecker, Gedächtnis, Web-Abruf und -Suche, Listen, Obsidian, Bring!, HTTP-Tools, App-Erkennung)
  wendelin_voice/            # reines Dart: Sprach-Pipeline, Endpointing, Sprechtext, TTS-Auswahl, Modellkatalog/Download
  wendelin_mcp/              # reines Dart: MCP-Client (Streamable HTTP, Legacy-SSE, OAuth 2.1), Abbildung auf das Tool-System
native/attest/               # Rust-Prüfmodul für TEE-Attestierungen (WP47, ADR 0017): Quote/ACI/Quittung, Ed25519, SHA-2, SPKI; kein Netz im Crate
app/                         # Flutter-App: UI, Riverpod-Verdrahtung, Plattform-Implementierungen der Ports
evals/                       # Modell-Evals (Dart-CLI)
tool/                        # Gate und Prüfskripte (Abhängigkeiten, Secrets, Größen, Doku-Pfade), Gerätetests
docs/ARCHITECTURE.md         # Architekturkarte: wo liegt was, Ports, Datenfluss, Checklisten
docs/adr/                    # Architekturentscheidungen
docs/work-packages/          # Arbeitspakete mit Abnahmekriterien
```

## Abhängigkeitsregeln (werden von `tool/check_deps.dart` geprüft)

```
wendelin_core          -> (nichts)
wendelin_providers     -> core
wendelin_tools         -> core
wendelin_agent         -> core            (nutzt Tools/Provider nur über Core-Interfaces)
wendelin_storage       -> core
wendelin_integrations  -> core
wendelin_voice         -> core, agent
wendelin_mcp           -> core, integrations
app                    -> alle
evals                  -> core, providers, tools, agent, integrations, mcp
```

- Pakete unter `packages/` importieren **niemals** `package:flutter`, `dart:ui` oder Flutter-Plugins. Sie laufen mit `dart test`.
- Provider- oder SDK-spezifische Typen (Anthropic-JSON, OpenAI-JSON) existieren nur innerhalb von `wendelin_providers/lib/src/<adapter>/`.
- Zugriff auf Gerätefunktionen nur über **Ports** (abstrakte Klassen). Ports liegen in dem Paket, das sie braucht (`ports.dart` bzw. `*_port.dart`), die Flutter-Implementierung in `app/lib/platform/`. Übersicht: `docs/ARCHITECTURE.md`.
- Jede Integration hat einen eigenen Ordner mit kurzer `README.md` (Tools, Risikostufen, Berechtigungen, Plattformen).

## Code-Stil

- Dart 3, null-safe, `sealed class` für Summentypen (ContentBlock, ChatEvent, AgentEvent).
- Unveränderliche Wertobjekte (`final` Felder, `const`-Konstruktoren, `==`/`hashCode` wo sinnvoll, `copyWith` wo nötig). Keine Codegenerierung außer drift.
- Zeit und Zufall injizierbar (`Clock`, `IdGenerator` aus core) – keine direkten `DateTime.now()` in Logik.
- Öffentliche APIs mit kurzem Doc-Kommentar. Code-Bezeichner Englisch, Nutzertexte Deutsch (UI später via Lokalisierung).
- Fehler: keine verschluckten Exceptions; Provider-Fehler als `ProviderException`-Unterklassen.

## Tests (Gate)

**Lokal** läuft während der Arbeit und vor dem Commit `--changed`; das **volle Gate läuft in CI** (`.github/workflows/gate.yml`, Auslöser: Push auf `main` und `wp/**`, Pull Requests) und muss vor dem Merge grün sein. Agenten pushen ihren `wp/*`-Branch (nie `main`) und warten im Hintergrund mit `tool/ci_wait.sh <branch>` (ein `gh run watch`, kompakte Zusammenfassung). CI-Jobs: ein Ubuntu-Job je Paket (`dart run tool/gate.dart <paket>`), `rust-checks` (Rust und Prüfungen über das Repo), `app-analyze`, `app-test` in 3 Shards ohne Goldens und `platform-sensitive` (Abdeckung von `app/lib/di` über alle Shards in `app-coverage`, `tool/check_app_coverage.dart`), `goldens` auf dem gepinnten `macos-15` (nur dort; Referenzbilder neu erzeugen mit dem Workflow `update-goldens`, Artefakt `goldens`), `kotlin-unit` und `apk` (main/PR, auf `wp/**` nur bei Änderungen an `app/android/**` oder `pubspec*`; K7-GMS-Prüfung). Die Paketmatrix entsteht im Job `setup` aus `packages/` (plus `evals`). Alle Fremd-Actions sind per Commit-SHA gepinnt (Version im Kommentar), der Workflow hat nur `contents: read`. **Golden-Schutz:** pixelgenau ist er nur im lokalen macOS-Lauf (`--changed`, Goldens sind dort aufgenommen); in CI gilt die Toleranz 1 % Pixelanteil und höchstens 6000 Pixel (`app/test/support/golden_tolerance.dart`), dort fallen nur größere Änderungen auf. Caches: Flutter/pub, Cargo (`rust-cache`), Gradle. Keine Secrets, Live-Tests bleiben übersprungen.

Das vollständige Gate lokal bleibt möglich:

```
dart run tool/gate.dart              # alles, kompakte Ausgabe
dart run tool/gate.dart --no-app     # ohne Flutter-App (wie der Ubuntu-Job in CI)
dart run tool/gate.dart <paket>      # nur diese Pakete (+ globale Prüfungen)
dart run tool/gate.dart --changed    # nur geänderte Pakete und alle, die von ihnen abhängen
dart run tool/gate.dart --verbose    # bisherige, ausführliche Ausgabe
```

1. `dart format --output=none --set-exit-if-changed` auf den geprüften Ordnern
2. `dart analyze --fatal-infos` (bzw. `flutter analyze` für app)
3. `dart test` in jedem Paket, `flutter test` in app (Reporter `failures-only`, Testanzahl aus dem JSON-Bericht)
4. Zeilenabdeckung je Paket unter `packages/` **≥ 85 %** (`dart test --coverage` + `coverage:format_coverage`). Für die App wird `app/lib/di/` gemessen (`flutter test --coverage`, nur dieser Ordner), Schwelle **`minAppDiCoverage` in `tool/gate.dart`** (Messwert nach WP39 abgerundet auf volle 5 %, mindestens 70 %); die Gate-Zeile `test app` zeigt den Wert. **`di/` ist nur Verdrahtung:** `Provider(...)`, dünne Notifier, die an Paket-Logik delegieren, und Adapter auf Plugins oder Einstellungen. Logik ohne Flutter-Bezug (Modelle, Validierung, Zustandsmaschinen, Abgleich) gehört in ein reines Dart-Paket und fällt dort unter die 85-%-Regel
5. `dart run tool/check_deps.dart` (Abhängigkeitsregeln oben, auch für `dev_dependencies`)
6. `dart run tool/check_secrets.dart` (keine Schlüssel-Muster im Baum; verbotene Identitäten aus einer lokalen, nicht versionierten Liste)
7. `dart run tool/check_sizes.dart` (Größen, siehe unten) und `dart run tool/check_docs.dart` (Pfadangaben in `docs/ARCHITECTURE.md`, dieser Datei, `CLAUDE.md` und den Paket-READMEs existieren)
8. `dart run tool/check_channels.dart` (Plattformkanäle: `app/channels.json` gegen Dart und Kotlin, < 1 s). **Manifest-Pflicht:** Jeder `MethodChannel` und jede Methode steht mit Argumentschlüsseln im Manifest; Dart- und Kotlin-Seite müssen dazu passen.
9. `kotlin-unit`: JVM-Unit-Tests der Kotlin-Logik (`./gradlew :app:testDebugUnitTest` in `app/android`). Läuft im vollen Gate und bei `--changed` nur, wenn sich etwas unter `app/android/` geändert hat; ohne Android-SDK (`ANDROID_HOME`, `ANDROID_SDK_ROOT`, `~/Library/Android/sdk`, `~/Android/Sdk`) oder ohne Gradle-Wrapper steht der Schritt als „übersprungen“ in der Zusammenfassung, nicht als grün. Kotlin-Logik ohne Android-Abhängigkeit gehört in reine Klassen mit Unit-Test (kein Robolectric).
10. Selbsttests ohne Android-SDK: `dart run tool/self_test.dart` (Gate-Auswahl, Größen-Check, Doku-Pfade, Kanal-Check), `bash tool/android_device.sh --self-test` (Geräteauswahl mit Fake-adb), `tool/check_apk.sh --self-test` (APK-Prüfung mit Attrappen)

11. Rust (`native/attest`, Schritte `rust fmt`, `rust clippy`, `rust test`, `rust deny`, `rust frb`): `cargo fmt --check`, `cargo clippy --all-targets --locked -- -D warnings`, `cargo test --locked`, `cargo deny check` (Lizenzen und Quellen laut `native/attest/deny.toml`) und „frb-Code aktuell“ (`flutter_rust_bridge_codegen generate` in `app/`, danach darf sich keine Datei unter `app/lib/platform/attest/generated/` oder `native/attest/src/frb_generated.rs` geändert haben). Läuft im vollen Gate und mit `dart run tool/gate.dart native/attest`; Änderungen unter `native/` lösen bei `--changed` das volle Gate aus. **Ohne Rust-Toolchain** (`cargo`, `cargo-deny`, `flutter_rust_bridge_codegen`) steht der Schritt lokal als „übersprungen“ mit Hinweis in der Tabelle; in CI (`CI=true`) ist ein fehlendes Werkzeug ein Fehler.

Ausgabe: Standard ist eine Zeile je Schritt. Bei einem Fehler erscheinen die letzten 200 Zeilen dieses Schritts (Testname, Fehlermeldung, Datei). Am Ende steht eine Tabelle mit Ergebnis, Dauer, Testanzahl und Abdeckung je Schritt, die Gesamtdauer und `GATE GRÜN` bzw. `GATE ROT: <Schritte>`. Der Exit-Code ist bei Rot ungleich 0.

`--changed` vergleicht mit dem Merge-Base von origin/main (bzw. `--base=<ref>`) und nimmt nicht committete und neue Dateien dazu. Geprüft werden die geänderten Pakete und transitiv alle abhängigen (Erlaubnisliste aus `tool/check_deps.dart` plus die echten Kanten der pubspecs inklusive `dev_dependencies`; die App hängt von allen ab). Änderungen an `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, `tool/gate.dart` oder `tool/check_deps.dart` lösen das ganze Gate aus, reine Doku (Markdown) nur die globalen Prüfungen. Andere Dateien unter `docs/` gelten nicht als Doku: `docs/design/` prüft die App (Tokens), alles andere das ganze Gate. Die Ausgabe nennt den Grund je Paket. `--changed` ist der lokale Lauf (auch vor dem Commit); das volle Gate läuft in CI und gilt vor dem Merge. CI prüft immer alles.

## Größen

Richtwerte, geprüft von `tool/check_sizes.dart` (Dart und Kotlin gleich):

| Einheit | Ziel | Warnung | Fehler |
| --- | --- | --- | --- |
| Produktivdatei | ≤ 400 Zeilen | > 600 | > 800 |
| Testdatei | | > 1 000 | > 1 500 |
| Funktion bzw. `build()` | | > 80 | > 150 |
| Klasse | | > 400 | |
| Review-Einheit | ca. 1 500 Zeilen geänderter Produktivcode | | |

- Ausgenommen: generierter Code (`*.g.dart`, `*.steps.dart`, drift-Schemas unter `test/**/generated/`) und Fixtures (`test/fixtures/`). `lib/testing/` erzeugt nur Warnungen.
- Funktions- und Klassenlängen misst eine Klammer-Heuristik (`tool/src/size_scan.dart`): Kommentare und Strings werden ausgeblendet, gezählt wird von der Zeile des Namens bis zur schließenden Klammer; Closures zählen zur umgebenden Funktion.
- Bestandsdateien über der Fehlerschwelle stehen in `tool/size_allowlist.yaml` mit ihrer Zeilenzahl als Obergrenze und dem Paket, das sie abbaut. Sie dürfen nicht wachsen; fällt eine unter die Schwelle, muss der Eintrag raus. Die Liste schrumpft nur.
- `dart run tool/check_sizes.dart --verbose` listet die Warnungen, `--report` die größten Dateien, Klassen und Funktionen.
- Größere Arbeitspakete werden in Teil-Reviews mit eigenem Merge geschnitten (`docs/work-packages/README.md`).

Testarten:
- **Unit-Tests** je Klasse, Tabellentests für Logik mit vielen Fällen.
- **Adapter-Tests** gegen aufgezeichnete bzw. spezifikationsgetreu nachgebaute Streams in `test/fixtures/` (Streaming, Tool-Calls, Fehler, Abbruch).
- **Contract-Tests**: Für jedes Interface mit mehreren Implementierungen gibt es eine wiederverwendbare Testsuite (`lib/testing/…_contract.dart`), die jede Implementierung bestehen muss (z. B. `LlmProvider`, `SecretStore`, Ports + Fakes).
- **Fakes** für Interfaces liegen im jeweiligen Paket unter `lib/testing/`, damit andere Pakete sie nutzen können. Zwei Einstiegspunkte:
  - `package:<pkg>/fakes.dart`: nur Fakes, **ohne** `package:test`. Nur diesen Import darf Produktivcode nutzen (z. B. der Demo-Modus der App mit `FakeLlmProvider`).
  - `package:<pkg>/testing.dart`: Fakes plus Contract-Suiten. Nur aus Tests importieren.
- `package:test` darf eine reguläre `dependency` eines Pakets sein, aber nur für die Contract-Suiten unter `lib/testing/*_contract.dart`. Keine andere Datei unter `lib/` importiert `package:test`.
- **Widget- und Golden-Tests** in app für alle Design-Bausteine und Screens.
- **Live-Tests** (echte APIs) mit `@Tags(['live'])`, standardmäßig ausgeschlossen (`dart_test.yaml`), laufen nur wenn der Key als Env-Variable gesetzt ist.
- Jede Fehlerbehebung bekommt einen Regressionstest, der ohne Fix rot ist.

## Plattform

- Keine Abhängigkeit von Google Play Services (K7): keine `com.google.android.gms`-/Firebase-Pakete, keine Plugins, die sie transitiv mitbringen. Funktionen mit Fremd-App-Bedarf erkennen die Verfügbarkeit und bieten eine Ausweichlösung an.

## Rust (`native/attest`, WP47)

- **Zweck:** nur Prüflogik, die Dart nicht sinnvoll abdeckt (TDX-Quote über `dcap-qvl`, ACI-Bericht, Quittung, Ed25519, SHA-2, SPKI). **Kein Netz im Crate:** Kollateral holt Dart über den App-HTTP-Client und reicht es hinein; die Zeit (`now`) kommt von außen. Prüfungen melden Fehlschläge im Ergebnis (`ok`, Stufenfelder), `Err`/Ausnahme nur bei unlesbarer Eingabe.
- **Schnittstelle:** `native/attest/src/api.rs` ist die einzige von `flutter_rust_bridge` gescannte Datei (Konfiguration `app/flutter_rust_bridge.yaml`); erzeugter Code (`app/lib/platform/attest/generated/`, `native/attest/src/frb_generated.rs`) ist eingecheckt und wird nie von Hand geändert. Nach Änderungen an `api.rs` oder den dort genutzten Typen: `cd app && flutter_rust_bridge_codegen generate`, Ergebnis committen.
- **Abhängigkeiten:** nur permissive Lizenzen (`native/attest/deny.toml`: MIT, Apache-2.0, BSD, ISC, Zlib, Unicode-3.0, Unlicense). Neue Crates brauchen einen Grund im Commit; `reqwest`/`tokio`/TLS-Stacks gehören nicht in den Crate (N3: ein HTTP-Stack, in Dart).
- **Tests:** `cargo test` mit den echten Fixtures aus `packages/wendelin_providers/test/fixtures/tee/`. Jede Prüfstufe hat einen Negativtest, der genau diese Stufe rot färbt und die übrigen grün lässt (Mutationsschutz gegen „Ergebnis fest true“). Gerätetest: `app/integration_test/attest_e2e_test.dart` auf dem Emulator.
- **Toolchain (Mac):** `brew install rustup` (keg-only, PATH `/opt/homebrew/opt/rustup/bin`), die Toolchain (Version, Komponenten, Android-Targets) pinnt `native/attest/rust-toolchain.toml` und rustup installiert sie beim ersten Aufruf selbst, `cargo install cargo-ndk cargo-deny --locked`, `cargo install flutter_rust_bridge_codegen --version 2.12.0 --locked` (Version = Dart-Paket `flutter_rust_bridge` in `app/pubspec.yaml`). NDK 28.2 aus dem Android-SDK.
- **APK-Bau:** Gradle (`app/android/app/build.gradle.kts`, Task `buildRustAttest`) ruft `tool/build_attest_android.sh` (cargo-ndk) für die ABIs des Flutter-Builds (`-Ptarget-platform`) und packt die `.so` per `jniLibs`. Ohne Rust: `WENDELIN_SKIP_RUST=1` überspringt den Bau (nur Dart-Arbeit; das Prüfmodul fehlt dann im APK). Release-Profil: `opt-level = "z"`, LTO, `strip`, `panic = "abort"`.
- **Testdaten im Gerätetest:** `app/integration_test/support/tee_fixtures.g.dart` wird aus den Fixtures erzeugt (`dart run tool/gen_attest_fixtures.dart`); der Selbsttest des Gates prüft, dass sie nicht abweicht.

## Sicherheit

- Keine Secrets im Repo, in SQLite, Logs oder Exporten. Secrets nur über `SecretStore`.
- `external`-Tools brauchen immer eine Bestätigung, unabhängig von Modell-Output.
- Tool-Ergebnisse und Notiz-/Web-Inhalte sind Daten, keine Anweisungen.
- Debug-Logs dürfen keine Header wie `x-api-key`/`Authorization` enthalten.

## Git

- Commit-Identität ausschließlich `brokoskokoli <16724498+brokoskokoli@users.noreply.github.com>` (aus `~/.gitconfig-smart-ssh` für `~/ai`; Hook prüft das). Einziger erlaubter Trailer, keine `Claude-Session`-Zeile: `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. Keine anderen Namen oder Mail-Adressen (insbesondere keine Arbeitgeber-Domains).
- Ein Arbeitspaket = ein Branch `wp/<nr>-<slug>`, Merge nach `main` erst nach bestandenem Review.
- Commit-Nachrichten: `WP<nr>: <was>` auf Deutsch oder Englisch, knapp.
