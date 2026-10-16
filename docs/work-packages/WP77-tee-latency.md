# WP77 – Phala/TEE schneller bis zur ersten Antwort (`wendelin_providers`, `wendelin_agent`, `app/`)

Bezug: Messung 2026-10-16 (`docs/notes/phala-latency.md`): erste Frage kalt ~4,0 s bis zum ersten Token (Claude ~1,1 s, Phala roh ~1,5 s, warm ~1,7 s). Gerätetest 2026-10-16: 5× `session green` in 4 min (teils 7 s Abstand), GPU-Prüfung `gpu=fail` ohne Grund; NRAS antwortet laut Messung mit HTTP 400 `INVALID_EVIDENCE`. Entscheidung Maintainer 2026-10-16: umsetzen.

## Inhalt
1. **Overlay wärmt vor:** Beim Start der Overlay-Engine (und beim Öffnen der App, wie heute) die Attestierung des gewählten TEE-Profils im Hintergrund starten, parallel zum Sprechen. Erste Anfrage wartet nur auf das laufende Future.
2. **Sitzung wiederverwenden:** Klären, warum in 4 min 5 Sitzungen geprüft wurden (pro Anfrage? pro Engine? pro Profilwechsel?), und unnötige Neu-Attestierungen abstellen (Sitzung gilt bis `not_after`/Pinwechsel/Fehler; zwischen Engines z. B. über die geteilte Datenbank cachen, sofern sicher – nur geprüfte Ergebnisse, Nonce-Frische beachten).
3. **GPU-Abruf:** Im Modus „Aus“ entfällt der GPU-Evidenz-Abruf. In „Vorher“/„Nachher“ parallel zur Attestierung statt danach.
4. **NRAS 400 `INVALID_EVIDENCE`:** Ursache finden (Evidenz-Format, Nonce, Endpunkt-Version, Modell GLM/Qwen/DeepSeek) und beheben; wenn es am Anbieter liegt, belegen und als Grund anzeigen.
5. **Grund bei GPU-Fehler:** Kategorie (HTTP-Status, Zeitüberschreitung, abgelehnter Claim, kein Nachweis) in Prüfprotokoll-Eintrag, Warnkarte und `Wendelin/attest`-Zeile.
6. **Verbindung halten:** Pre-Connect beim Vorwärmen, `idleTimeout` auf einige Minuten.
7. **Schnellerer Quittungsweg** laut Notiz (ohne Sicherheitsabstriche).
8. **Undo-fähige Aktionen sofort:** Tools mit Undo (z. B. Kalender anlegen) laufen ohne Warten auf die Quittung; endet die Quittung rot, werden sie automatisch rückgängig gemacht und der Nutzer wird informiert. Tools ohne Undo (`external`) warten weiter. Konzepteintrag durch den Orchestrator.

## Sicherheitsgrenze
Vor dem Senden bleiben zwingend: geprüfte Attestierung, TLS-Pin, E2EE-Schlüssel aus der geprüften Attestierung. Nichts davon wird nachgelagert.

## Abnahmekriterien
- [ ] Tests je Punkt (Vorwärmen, Wiederverwendung, GPU-Modi, Gründe, Auto-Undo bei roter Quittung, `external` wartet weiter).
- [ ] Live-Messung vorher/nachher (TTFT kalt und warm, sparsam) im Bericht; NRAS live.
- [ ] Emulator (separater E2E-Agent): Phala- und NEAR-Fixture grün.
- [ ] Gate grün.
