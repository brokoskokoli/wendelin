# Zwischenablage (`clipboard`)

| Tool | Risiko | Zweck |
| --- | --- | --- |
| `clipboard__read` | read | Text der Zwischenablage, als Daten markiert, höchstens 10 000 Zeichen |
| `clipboard__write` | write | Text kopieren (höchstens 100 000 Zeichen). Undo stellt den vorherigen Text wieder her |

**Undo von `clipboard__write`**: Vor dem Schreiben wird der alte Inhalt gelesen und bis zum Verfall der Undo-Aktion im Speicher gehalten (nie persistiert). Folgen: Auf iOS kann dabei der Einfüge-Hinweis erscheinen; auf Android 10+ ist Lesen im Hintergrund verboten, dann wird trotzdem geschrieben, aber ohne Undo. Mit `ClipboardIntegration(port, undoReadsPrevious: false)` liest das Tool nichts und bietet kein Undo; WP08 kann das pro Plattform abschalten.

**Port**: `ClipboardPort` (`read`, `write`). Android 10+ erlaubt Lesen nur im Vordergrund; die Implementierung wirft dann `PortException(permissionDenied)`. iOS zeigt beim Lesen den Einfüge-Hinweis. Fake: `FakeClipboardPort`, Vertrag: `clipboardPortContract`.

**Berechtigung**: keine. **Plattformen**: Android, iOS. **Sensibel**: ja (die Zwischenablage kann Passwörter oder Adressen enthalten).
