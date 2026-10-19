# Datenschutz und Taint (K9, K10)

- Stufen: `PrivacyLevel` (`packages/wendelin_core/lib/src/provider/privacy_level.dart`), Untergrenze je Nachricht als `Message.privacyFloor`.
- Tool-Katalog je Zielstufe: sensible Integrationen nur für ausreichend geschützte Ziele in `packages/wendelin_tools/lib/src/registry/tool_registry.dart`; Nutzer-Markierung „sensibel“ in `app/lib/di/sensitivity.dart`.
- Ausblenden geschützter Ergebnisse, Privatsphäre-Untergrenze und Taint: `PrivacyScope` (`hiddenFor`, `messagesFor`, `raiseFloorToTaint`, `visibleMemories`) in `packages/wendelin_agent/lib/src/run/privacy_scope.dart`. Dass die Untergrenze nie sinkt, erzwingt `RunState.raiseFloor` in `packages/wendelin_agent/lib/src/run/run_state.dart`.
- Ablehnung von Aufrufen auf nicht sichtbare Tools: `ToolRound` in `packages/wendelin_agent/lib/src/run/tool_round.dart`.
- Eskalation unter die Stufe nur mit Rückfrage: `Escalation` in `packages/wendelin_agent/lib/src/run/escalation.dart`, Regel „Privat“ in `packages/wendelin_agent/lib/src/routing/routing_engine.dart` und `app/lib/di/routing.dart`.
- Sensible Inhalte (Secrets, Kartennummern) erkennen: `packages/wendelin_core/lib/src/safety/sensitive_content.dart`, Sperre beim Speichern in `packages/wendelin_storage/lib/src/sensitive_content.dart`.
