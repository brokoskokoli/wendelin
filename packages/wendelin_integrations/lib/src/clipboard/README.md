# Zwischenablage (`clipboard`)

| Tool | Risiko | Zweck |
| --- | --- | --- |
| `clipboard__read` | read | Text der Zwischenablage, als Daten markiert, höchstens 10 000 Zeichen |
| `clipboard__write` | write | Text kopieren (höchstens 100 000 Zeichen). Undo stellt den vorherigen Text wieder her (nur wenn er lesbar war) |

**Port**: `ClipboardPort` (`read`, `write`). Android 10+ erlaubt Lesen nur im Vordergrund; die Implementierung wirft dann `PortException(permissionDenied)`. iOS zeigt beim Lesen den Einfüge-Hinweis. Fake: `FakeClipboardPort`, Vertrag: `clipboardPortContract`.

**Berechtigung**: keine. **Plattformen**: Android, iOS. **Sensibel**: ja (die Zwischenablage kann Passwörter oder Adressen enthalten).
