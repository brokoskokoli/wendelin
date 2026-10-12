# Gedächtnis (`memory`)

| Tool | Risiko | Zweck |
| --- | --- | --- |
| `memory__save` | write | Etwas merken, **nur auf ausdrücklichen Wunsch** („merk dir …“). Kategorie `person`, `preference`, `fact` oder `project`. Undo vergisst den Eintrag |
| `memory__search` | read | Einträge suchen (Standard 5, höchstens 20) |
| `memory__forget` | write | Eintrag per Id vergessen. Undo speichert ihn erneut (neue Id) |

**Schutzregel**: `sensitiveContentReason` weist Kartennummern (Luhn-geprüft), IBAN-Muster, „Passwort/PIN/Kennwort/API-Key … ist|: …“ und schlüsselartige Tokens ab. Das Tool prüft vor dem Port; der Port (App: `MemoryRepository`) prüft selbst noch einmal und wirft `PortException(rejected)`, was das Tool als Fehler meldet. Andere Kategorien als die vier erlaubten (z. B. Gesundheit, Finanzen) lehnt das Schema ab. Gesundheits- oder Finanzthemen werden nicht per Schlüsselwort erkannt; die Tool-Beschreibung beschränkt das Speichern auf ausdrückliche Wünsche.

**Quelle**: `session:<sessionId>`.

**Port**: `MemoryStorePort` (`save`, `search`, `forget` → entfernter Eintrag, `list`). Die App verdrahtet ihn mit `MemoryRepository` aus `wendelin_storage`. Fake: `FakeMemoryStore`, Vertrag: `memoryStoreContract`.

**Berechtigung**: keine. **Plattformen**: Android, iOS. **Sensibel**: ja.
