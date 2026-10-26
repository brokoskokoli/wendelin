# Datenschutz und Taint (K9, K10)

- Stufen: `PrivacyLevel` (`packages/wendelin_core/lib/src/provider/privacy_level.dart`), Untergrenze je Nachricht als `Message.privacyFloor`.
- Tool-Katalog je Zielstufe: sensible Integrationen nur für ausreichend geschützte Ziele in `packages/wendelin_tools/lib/src/registry/tool_registry.dart`; Nutzer-Markierung „sensibel“ in `app/lib/di/sensitivity.dart`.
- Ausblenden geschützter Ergebnisse, Privatsphäre-Untergrenze und Taint: `PrivacyScope` (`hiddenFor`, `messagesFor`, `raiseFloorToTaint`, `visibleMemories`) in `packages/wendelin_agent/lib/src/run/privacy_scope.dart`. Dass die Untergrenze nie sinkt, erzwingt `RunState.raiseFloor` in `packages/wendelin_agent/lib/src/run/run_state.dart`.
- Ablehnung von Aufrufen auf nicht sichtbare Tools: `ToolRound` in `packages/wendelin_agent/lib/src/run/tool_round.dart`.
- Eskalation unter die Stufe nur mit Rückfrage: `Escalation` in `packages/wendelin_agent/lib/src/run/escalation.dart`, Regel „Privat“ in `packages/wendelin_agent/lib/src/routing/routing_engine.dart` und `app/lib/di/routing.dart`.
- Sensible Inhalte (Secrets, Kartennummern) erkennen: `packages/wendelin_core/lib/src/safety/sensitive_content.dart`, Sperre beim Speichern in `packages/wendelin_storage/lib/src/sensitive_content.dart`.

## Entwicklermodus (WP148)
Bewusste Ausnahme von der Positivliste des Logs (`app/lib/voice/voice_log.dart`: nur Zahlen, nie Inhalt): Ist der Entwicklermodus an (Einstellung `debug.developerMode`, Schalter: 10× „System“ in Einstellungen → App-Sprache), schreibt `devLog` (`app/lib/voice/dev_log.dart`) zusätzlich Zeilen mit Inhalt unter dem Tag `Wendelin/dev:` (`adb logcat | grep Wendelin/dev`).
- Inhalt: erkannter Text (`stt-text` in `app/lib/platform/voice/whisper_stt.dart`, `wake-strip` und `stt-reject` über `VoicePipeline.contentLog`), je Werkzeugaufruf `tool-call`/`tool-result`, `model-text`, bei Abbruch `agent-failed` mit `agent-round` je Runde (`app/lib/voice/dev_agent_log.dart`, eingehängt in `AgentController._onEvent`, also Tipp-Chat und Sprache gleich).
- Schutz: Felder gekürzt (300 Zeichen), Schlüssel/Tokens/Passwörter über `redactSecrets`, `Bearer`/`sk-…` maskiert, erkannter sensibler Text (`detectSensitiveContent`) ganz `***`. Ohne Flag schreibt `devLog` nichts (Test `app/test/dev/dev_log_test.dart`, `dev_wiring_test.dart`).
- Flag je Engine: gelesen beim Start (`runWendelinApp`) und neu bei jeder Sprachsitzung (`VoiceController.start`) und Anfrage (`AgentController._start`, `refreshDevLogFlag`), Umschalten wirkt daher ohne Neustart in App, Overlay und Station. Die Erkenner- und Wake-Engine haben keine Datenbank und bleiben aus (kein Mitschreiben fremder Sprache aus anderen Apps).
- Sichtbar: Hinweis in den Einstellungen, solange der Modus an ist; „Bonus Hinweisbegriffe“ nur dann in der Sprach-Erweitert-Ansicht.
