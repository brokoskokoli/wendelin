# WP29 – End-to-End M3, Evals, Geräte-Testanleitung, Demo

Abhängig von: WP21–WP28. Andockpunkte: `tool/e2e_android.sh`, `tool/android_device.sh`, `evals/`, `FakeMcpServer` (WP22), `docs/notes/`. Konzept-Bezug: DoD M3, „Teststrategie“ (Routing-Tabellentests, Modell-Eval, Integrationstests auf AOSP ohne GMS, K7), „Hinweise für den Coding-Agenten“ (Demo-Anleitung).

## Inhalt
- **Test-MCP-Server für den Host**: `tool/mcp_test_server.dart` startet `FakeMcpServer` mit einigen harmlosen Tools (`echo`, `get_time` read, `toggle_light` write, `delete_thing` destructive) und optionalem Bearer-Token aus einer Umgebungsvariable; lauscht auf einem Port, den der Emulator über `10.0.2.2` erreicht.
- **E2E auf dem Emulator** (`tool/e2e_android.sh` erweitern, nur `Wendelin_AOSP_35`, Serial explizit `emulator-xxxx`, siehe M3.md): Profil „Claude“ (Fake-Provider über die Debug-Overrides wie in WP19, `app/lib/debug/device_test_overrides.dart`) und Default-Profil anlegen, Regel „Starkes Modell“ (Präfix „Claude“) aktiv; „Claude, wie spät ist es?“ → Audit-Log zeigt Routing auf das Claude-Profil; MCP-Server `http://10.0.2.2:<port>` mit Bearer einrichten, Tools erscheinen, ein `read`-Tool läuft, das `destructive`-Tool fragt nach; App-Erkennung (WP25) und HTTP-Tool gegen den Test-Server (`http__…`).
- **Live (sparsam, `@Tags(['live'])`)**: Routing-Test mit echtem Anthropic-Key, kleinstes Modell (Haiku), ein Satz „Claude, sag nur OK“ → Antwort kommt vom Claude-Profil; optional ein MCP-Live-Call vom Desktop gegen den Test-Server mit echtem LLM (OpenAI-kompatibel, kleinstes Modell), ≤ 2 Anfragen. Keys aus `~/.wendelin-live.env`, nie ausgeben.
- **Evals** (`evals/`): Fälle für Bring! (aus WP24-README), HTTP-Tool (Home-Assistant-ähnliche Definition mit Fake-Backend) und MCP-Tools (über `FakeMcpServer` im Prozess), je de/fr/en; Routing-Tabellentests aus WP21 in die Eval-Ausgabe übernehmen („welche Regel greift“). Falls `evals` dafür `wendelin_mcp` braucht: Abhängigkeitsregel `evals -> … mcp` ergänzen.
- **Geräte-Testanleitung für den Maintainer** (`docs/notes/m3-device-test.md`): Tailscale auf Handy und Homeserver, MCP-Server (z. B. Home Assistant MCP oder stdio-Server hinter einem stdio-zu-HTTP-Proxy) erreichbar unter `100.x`/`*.ts.net`, Einrichtung in der App, Regel „Claude, …“ mit echtem Claude-Profil, Checkliste für die DoD. Der Maintainer führt den Gerätetest selbst aus; Agenten installieren nie auf sein Gerät.
- **Demo-Anleitung M3** im README; Ergebnisse in `docs/notes/m3-e2e-<datum>.md`.

## Abnahmekriterien
- [ ] DoD auf dem Emulator nachgewiesen: Routing „Claude, …“ → Claude-Profil (Audit-Log), MCP-Server über `10.0.2.2` liefert Tools, Bestätigung bei `destructiveHint`.
- [ ] E2E-Skript läuft nur mit `emulator-*`-Serial und `ro.kernel.qemu=1`; Selbsttest im Gate grün; kein `E2E_ALLOW_DEVICE`.
- [ ] Live-Tests getaggt, standardmäßig übersprungen, laufen mit gesetzten Keys einmal grün (Ergebnis mit Kosten in den Notizen).
- [ ] Eval-Fälle für Bring!, HTTP-Tool und MCP vorhanden und mit Fake-Backends grün.
- [ ] Geräte-Testanleitung und Demo-Anleitung vorhanden; Konzeptabweichungen im Abschlussbericht gelistet.
- [ ] Gate grün, APK baut, `tool/check_apk.sh` grün.
