# Glossar der App-Texte (de / en / fr)

Einheitliche Begriffe für `app/lib/l10n/app_{de,en,fr}.arb`. Neue Texte folgen diesem Glossar; wer einen neuen Fachbegriff einführt, trägt ihn hier ein. Siehe auch `docs/ENGINEERING.md` (Abschnitt „Texte“).

| Deutsch | English | Français | Hinweis |
|---|---|---|---|
| Wendelin | Wendelin | Wendelin | Eigenname, nie übersetzen |
| Sprachmodell | language model | modèle de langage | das LLM hinter dem Provider |
| Provider | provider | fournisseur | Anbieter des Sprachmodells (Claude, OpenAI, Homeserver …) |
| API-Schlüssel | API key | clé d’API | |
| Aktivierungswort | wake word | mot d’activation | Wake-Word-Funktion; Dienst = „Hintergrunddienst“ / background service / service d’arrière-plan |
| Overlay | overlay | overlay | schwebendes Fenster über anderen Apps; kein französisches Wort, „Overlay“ bleibt |
| Routing | routing | routage | Regeln, welche Anfrage an welches Modell geht |
| Regel | rule | règle | |
| Spracheingabe / Sprachausgabe | voice input / voice output | saisie vocale / sortie vocale | gilt für Mikrofon bzw. Vorlesen |
| Vorlesen | read aloud | lecture à voix haute | |
| Bestätigung | confirmation | confirmation | Rückfrage vor einer Aktion |
| Berechtigung | permission | autorisation | Android-Berechtigung |
| Werkzeug | tool | outil | Fähigkeiten des Assistenten (Kalender, Listen …) |
| Integration | integration | intégration | |
| Einstellungen | settings | paramètres | |
| TEE | TEE (trusted execution environment) | TEE (environnement d’exécution de confiance) | Beim ersten Auftreten auf einer Seite ausgeschrieben, danach „TEE“ |
| Attestierung | attestation | attestation | Nachweis, dass der Server in einem echten TEE läuft |
| Quittung | receipt | reçu | Signierter Nachweis der Prüfung zu einer Antwort |
| Prüfprotokoll | verification log | journal de vérification | Liste der Attestierungen |
| Prüfstufe | verification step | étape de vérification | die einzelnen Schritte einer Attestierung (Zertifikat, Hardware, Messwerte …) |
| GPU-Prüfung | GPU check | vérification du GPU | |
| Messwert | measurement | mesure | Hash des gestarteten Codes |
| Vertrauensanker | trust anchor | ancre de confiance | |
| Zertifikatskette | certificate chain | chaîne de certificats | |
| Sitzung | session | session | Verbindung mit dem Modell; „Gespräch“ = conversation / conversation |
| Gespräch | conversation | conversation | |
| Notiz | note | note | Obsidian |
| Tresor | vault | coffre | Obsidian-Vault |
| Einkaufsliste | shopping list | liste de courses | |
| Privatmodus | private mode | mode privé | |
| Kosten | costs | coûts | |
| Audit-Protokoll | audit log | journal d’audit | Protokoll der ausgeführten Aktionen |
| GPU-Prüfung: Aus / Vorher / Nachher | GPU check: Off / Before / After | vérification du GPU : Désactivée / Avant / Après | Modi der GPU-Prüfung über NVIDIA |
| Nachweis (GPU) | evidence | preuve | GPU-Nachweis = GPU evidence / preuve GPU |
| Token (Home Assistant) | token | jeton | „Long-Lived Access Token“ bleibt englisch/ Home-Assistant-Begriff |

Tonfall: Deutsch duzt („Schalte ein …“), Englisch ist knapp und im Imperativ, Französisch siezt („Activez …“, „vous“). Apostrophe in ARB-Texten immer als ’ schreiben, keine geschweiften Klammern im Text.
