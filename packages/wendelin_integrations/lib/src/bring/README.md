# Bring! Einkaufsliste (`bring`)

Einkaufslisten der App Bring! über deren **inoffizielle** REST-API (wie sie die Home-Assistant-Integration nutzt). Login mit dem Bring!-Konto des Nutzers. Die API ist nicht dokumentiert und kann sich jederzeit ändern; deshalb ist alles defensiv gebaut und jede unerwartete Antwort führt zu einem klaren Fehler statt zu einem Absturz.

| Tool | Risiko | Zweck |
| --- | --- | --- |
| `bring__list_lists` | read | Listen des Kontos, Standardliste markiert (`default: true`); als Daten markiert |
| `bring__get_items` | read | `list` optional (sonst Standardliste): offene Artikel mit Mengenangabe (`spec`) und die letzten 20 gekauften (`recently_bought`, Rest als `recently_more`); als Daten markiert |
| `bring__add_items` | write | `list` optional, `items: [{name, spec?}]` (bis 30, auch nur Namen als Text). Bereits offene Artikel (Groß/Klein, Umlaute, Leerzeichen egal) werden nicht doppelt angelegt (`already_present` mit der vorhandenen Angabe). Zuletzt gekaufte Artikel werden unter ihrem Bring!-Namen zurückgeholt. Undo entfernt genau die hinzugefügten Artikel, die noch offen sind; vorher zuletzt gekaufte gehen dorthin zurück. Scheitert ein Artikel, nachdem andere schon eingetragen sind, bricht das Tool ab und meldet ein normales Ergebnis mit `added`, `not_added`, `error` („teilweise hinzugefügt“) samt Undo für den eingetragenen Teil |
| `bring__remove_item` | write | Artikel löschen (erst offene, dann zuletzt gekaufte). Undo legt ihn mit gleicher Angabe wieder an (bzw. wieder unter „zuletzt gekauft“) |
| `bring__complete_item` | write | Artikel als gekauft markieren (nach „zuletzt gekauft“). Ist er dort schon → Hinweis `already_bought`. Undo legt ihn mit gleicher Angabe zurück auf die offene Liste |

**Auflösung** wie bei den Listen (K6, `common/matching.dart`): gleich → gleicher Wortstamm (Plural/Singular, „Getränk“ ≈ „Getränke“) → ganze Wörter („Urlaub“ ≈ „Urlaub Italien“). Mehrere Kandidaten auf derselben Stufe → „Mehrdeutig … Bitte nachfragen“. Treffer nur über ganze Wörter nehmen lesende Tools und `complete_item` (rückgängig machbar); Listenauflösung schreibender Tools und `remove_item` antworten „Meintest du …?“. Ohne `list` oder mit einem allgemeinen Namen, der keine Liste trifft („Bring-Liste“, „Einkaufsliste“, „shopping list“, „liste de courses“), gilt die Standardliste des Kontos (`bringListUUID`); fehlt sie und gibt es mehrere Listen → Rückfrage.

**Parallel**: Lesen-Prüfen-Schreiben einer Liste (auch Undo) läuft je Liste nacheinander (`FileQueue`, Schlüssel `bring:<listUuid>`), damit parallele Aufrufe nichts doppelt anlegen.

## Zugang, Sitzung und Fehlerzustand
- `BringSecrets` (App: `SecretStore`) liefert E-Mail/Passwort (`BringCredentials`) und speichert die Sitzung (`BringAuth`: Nutzer-Id, Access- und Refresh-Token, Standardliste; `toJson`/`fromJson` nur für den `SecretStore`). Nie SQLite, Einstellungs-JSON, Audit-Log, Debug-Log oder Export. `toString` beider Typen zeigt `<verborgen>`.
- `BringSession`: Sitzung aus dem Speicher, sonst aus `BringSecrets`, sonst Login. Wird ein Token abgelehnt (HTTP 401/403), wird **einmal** erneuert (Refresh-Token, bei Ablehnung neuer Login) und der Aufruf einmal wiederholt; 401 heißt „nicht ausgeführt“, das gilt auch für schreibende Aufrufe. Parallele Aufrufe teilen sich eine Erneuerung.
- **Dauerhafte Fehler pausieren** die Integration: Login abgelehnt, Token auch nach der Erneuerung abgelehnt (`permissionDenied`), unerwartete Antworten (`failed`: HTML statt JSON, fehlende Felder, andere Typen, unerwarteter Status). Dann ruft sie `onError(text)` (App: `ToolRegistry.reportError('bring', text)` → Zustand „Fehler“, Tools pausiert), und das Tool antwortet mit dem Text plus `bringFallbackHint` („Bring!-Tools sind pausiert. Ausweg: … Teilen an die Bring!-App“).
- **Vorübergehende Fehler pausieren nicht** (`unavailable`: offline, Zeitüberschreitung, 429, 5xx, auch beim Erneuern des Tokens; dann kein Login-Ersatz): nur der Aufruf scheitert, mit `bringRetryHint` („Bitte später erneut versuchen. Ausweg: … Teilen an die Bring!-App“). Die 429-Sperre im Client bleibt bestehen.
- Kein Fehlerzustand bei „nicht eingerichtet“ (Setup-Schritt fehlt), unbekannter Liste/Artikel oder Rückfragen.
- `reconnect()` prüft die Verbindung (z. B. Knopf „Erneut versuchen“ in WP28) und ruft bei Erfolg `onRecovered` (App: `clearError`); `signOut()` verwirft die Sitzung, wenn sich der Login ändert.
- Setup-Schritt `bring_login` (Art `login`): fehlen Zugangsdaten → „Einrichtung nötig“. `checkAvailability` ist immer „verfügbar“ (die API reicht, die App ist nicht nötig). **Sensibel**: nein.

## Fallback über die App (Umsetzung WP28)
`BringAppFallback`: Paket `ch.publisheria.bring`, `shareText(items)` (eine Zeile je Artikel, Angabe in Klammern) für einen Share-Intent an die Bring!-App, wenn die API scheitert; `note` als rein informativer Hinweis in den Einstellungen.

## HTTP-Client (`HttpBringApi`)
**Quelle**: Endpunkte, Kopfzeilen und Felder nach dem Open-Source-Python-Client [`bring-api`](https://github.com/miaucl/bring-api) (MIT, von der Home-Assistant-Integration `bring` genutzt), Dateien `bring_api/bring.py`, `const.py`, `types.py`, Stand Oktober 2026. Der Code ist nicht übernommen, nur die Form der API.

Basis `https://api.getbring.com/rest/`. Kopfzeilen bei jedem Aufruf: `X-BRING-API-KEY` (fester Client-Schlüssel der Bring!-Apps, in den Open-Source-Clients veröffentlicht, kein Nutzergeheimnis), `X-BRING-CLIENT: android`, `X-BRING-APPLICATION: bring`, `X-BRING-COUNTRY: DE`; nach dem Login zusätzlich `Authorization: Bearer <access_token>`, `X-BRING-USER-UUID`, `X-BRING-PUBLIC-USER-UUID`.

| Aufruf | Anfrage | Antwort (gelesene Felder) |
| --- | --- | --- |
| `login` | `POST v2/bringauth`, Formular `email`, `password` | `uuid`, `access_token` (Pflicht), `refresh_token`, `publicUuid`, `bringListUUID` |
| `refresh` | `POST v2/bringauth/token`, Formular `grant_type=refresh_token`, `refresh_token` | `access_token` (Pflicht), `refresh_token` (optional, sonst bleibt das alte) |
| `lists` | `GET bringusers/{uuid}/lists` | `lists[].listUuid`, `lists[].name` (Pflicht) |
| `items` | `GET v2/bringlists/{listUuid}` | `items.purchase[]` / `items.recently[]` mit `itemId` (Pflicht), `specification`, `uuid` |
| `saveItem` / `completeItem` / `removeItem` | `PUT v2/bringlists/{listUuid}/items`, JSON `{"changes": [{"itemId", "spec", "uuid"?, "operation", "accuracy"/"altitude"/"latitude"/"longitude": "0.0"}], "sender": ""}` mit `operation` = `TO_PURCHASE` / `TO_RECENTLY` / `REMOVE` | Antwort wird nicht gelesen (2xx genügt) |

**Fehlerabbildung** (`PortException`, Texte deutsch, ohne Passwort, Token oder Antwortinhalt): 401/403 (beim Login auch 400) → `permissionDenied`; 404 → `notFound`; 429 → `unavailable` mit Sperre bis `Retry-After` (Standard 60 s, höchstens 30 min), in der Zeit geht keine Anfrage raus; 5xx, Zeitüberschreitung (15 s), keine Verbindung → `unavailable`; HTML statt JSON, ungültiges UTF-8, fehlende Pflichtfelder, andere Typen, sonstige Statuscodes → `failed`. **Keine automatische Wiederholung** (auch nicht bei 5xx; der Python-Client wiederholt 502–504 einmal, wir bewusst nicht, damit schreibende Aufrufe nie doppelt laufen). Optionales `log` bekommt je Anfrage nur Operation und Status (`Bring! items → 200`).

**Grenzen**: Bring! speichert Katalogartikel unter deutschen Namen (`itemId`) und übersetzt sie in der App je Listensprache; wir zeigen und vergleichen die `itemId` ohne Übersetzung (bei deutschsprachigen Listen gleich). Artikel-Attribute (Kategorie, Bild, Dringlichkeit) werden ignoriert. Kein ETag-Cache.

## Nutzungsbedingungen
Die API ist nicht öffentlich und nicht für Drittanbieter freigegeben; ihre Nutzung ist von Bring! weder erlaubt noch dokumentiert. Wendelin nutzt sie nur mit dem eigenen Konto des Nutzers, sparsam (keine Abfragen im Hintergrund, keine Wiederholungen) und zeigt die Integration in den Einstellungen als „inoffiziell“ an (WP28). Bei Problemen bleibt der Weg über „Teilen“ an die Bring!-App. Vor einer Veröffentlichung im Store die Bedingungen erneut prüfen (Konzept, „Offene Fragen → Bring!“).

## Testhilfen
- `FakeBringApi` (Kontraktzustand: „Zuhause“ = Standardliste mit Milch (1 Liter), Äpfel, zuletzt Brot; „Büro“ mit Kaffee; `expireTokens`, `revokeRefresh`, `rejectTokens`, `failNext`), `FakeBringSecrets` aus `package:wendelin_integrations/fakes.dart`.
- `bringApiContract` aus `testing.dart`: Fake und `HttpBringApi` gegen eine nachgebaute API (`test/bring/bring_server.dart`, Antworten aus `test/fixtures/bring/`, nachgebaut, keine echten Konten, UUIDs oder Tokens).
- Live-Test `test/bring/bring_live_test.dart` (`@Tags(['live'])`), nur mit `BRING_EMAIL`/`BRING_PASSWORD`: Login, Listen, Testartikel anlegen und entfernen, Token erneuern.

## Eval-Fälle für WP29
- de: „Setz 2 Liter Milch auf die Bring-Liste“ → `bring__add_items(items: [{name: "Milch", spec: "2 Liter"}])` (`list` leer oder „Bring“)
- de: „Was steht auf der Einkaufsliste bei Bring?“ → `bring__get_items()` (ohne `list` oder `list: "Einkaufsliste"`)
- fr: « Ajoute des œufs et du beurre à ma liste Bring » → `bring__add_items(items: [{name: "Eier"|"œufs"}, {name: "Butter"|"beurre"}])`
- fr: « J'ai acheté le pain, coche-le dans Bring » → `bring__complete_item(item: "Brot"|"pain")`
- en: “Remove the coffee from the Büro list in Bring” → `bring__remove_item(list: "Büro", item: "Kaffee"|"coffee")`
- en: “Which Bring lists do I have?” → `bring__list_lists()`

**Berechtigung**: Internet (keine Laufzeitberechtigung). **Plattformen**: Android, iOS.
