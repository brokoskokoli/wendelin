# Briefing E2E-Agent

Lies zuerst `common.md` (Abschnitt „Geräte“), dann die im Auftrag genannten Tests in `app/integration_test/` und die Nutzung von `tool/e2e_android.sh`.

- **Gerät:** nur der Emulator, belegt = melden statt warten (`common.md`, „Geräte“).
- **Nichts committen.** Ein neuer oder geänderter Test bleibt uncommitted; nenne den Pfad im Bericht.
- **Fixtures** (synthetische Stimmen, z. B. mit macOS `say`) nur außerhalb des Repos, in dem im Auftrag genannten Ordner. Keine echten Sprachaufnahmen ins Repo.
- **Logs** nur auszugsweise im Bericht (relevante Zeilen, Tags Wendelin/voice, Wendelin/attest); keine Secrets ausgeben.
- **Übergabe:** an der Kontextgrenze (`AGENTS.md`) nach `../james-wt/handoff/<wp>-e2e.md`, Ende mit `ÜBERGABE: <pfad>`.
- **Bericht** (Länge: `AGENTS.md`): je Test/Szenario Ergebnis, Logbelege, bei Rot Ursache mit Datei:Zeile-Verdacht, ggf. neuer Test.
