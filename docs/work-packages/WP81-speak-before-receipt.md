# WP81 – Antwort sofort vorlesen, Haken danach; Profil nicht ständig neu aufbauen (`app/`, `wendelin_voice`, `wendelin_agent`)

Bezug: Nachtest APK 11193bb (2026-10-16, Testtelefon, `ergebnisse.md`): Tools wirken sofort, die gesprochene Antwort kommt erst 2–3 s später. Log: `speak source=answer` startet 14–16 ms nach `receipt green` (15:39:57.336 → .350; 15:41:01.642 → .658); `mic-stop`→`speak` 3,4 / 5,6 / 9,1 s. Außerdem 5× „Sitzung übernommen (Profil neu aufgebaut)“ in 6 min.

## Inhalt
1. **Ursache finden:** Wo wartet die Sprachausgabe auf die Quittung (z. B. Antwort-Strom endet erst nach Quittung, Satz-Puffer, Zwei-Versionen-Schutz, Overlay-Ausgabe hängt an `AttestationOutcome`)? Mit Test belegen.
2. **Fix:** Sätze vorlesen, sobald sie fertig sind (wie im Chat), unabhängig von der Quittung. Die Quittung zieht nur Haken/Warnkarte nach. Fällt die Quittung rot aus, gilt das bestehende Verhalten weiter (Warnhinweis, Auto-Undo aus WP77), die Sprachausgabe wird ggf. abgebrochen und ein kurzer gesprochener Hinweis folgt. Ausnahme bleibt: GPU „Vorher“ blockiert vor dem Senden (unverändert).
3. **Profil-Neuaufbau:** Klären, warum das Provider-Profil in kurzer Zeit mehrfach neu gebaut wird (Riverpod-Abhängigkeit, Einstellungs-Watch, Overlay-Start). Unnötige Neuaufbauten vermeiden; Sitzung bleibt erhalten. Log-Zeile mit Grund des Neuaufbaus.
4. **Messung:** Test bzw. Log zeigt `answer-complete`→`speak` < 100 ms unabhängig von der Quittung.

## Abnahmekriterien
- [ ] Unit-/Widget-Tests: Ausgabe startet vor `receipt green` (Fake-Provider mit verzögerter Quittung); roter Fall bricht ab und meldet.
- [ ] Test für ausbleibenden Profil-Neuaufbau bei gleichbleibenden Einstellungen.
- [ ] Emulator (separater E2E-Agent): Overlay-/Sprach-E2E mit TEE-Fixture grün. Gate grün.

## WP81b (freigegeben 2026-10-18)

In Tool-Runden startet der nächste Modellaufruf parallel zum Abruf der Quittung der vorigen Antwort (spart ca. 1–2 s je Runde). `external`-Tools warten weiter auf die geprüfte Quittung; eine rote Quittung bricht die laufende Runde ab, verwirft ihr Ergebnis und endet wie in WP81. Entscheidung Maintainer 2026-10-18.

## WP81c (Entscheidung Maintainer 2026-10-19)

Die Ausgabe der parallel gestarteten Runde (WP81b) wird **nicht** mehr bis zur grünen Quittung der vorigen Runde gepuffert, sondern wie in WP81 sofort angezeigt und vorgelesen. Fällt die Quittung der vorigen Runde rot aus: Sprachausgabe abbrechen, Text als verworfen markieren bzw. entfernen, gesprochener Hinweis, Undo wie bisher, dann sequentieller Neuaufruf wie in WP81b. `external`-Tools der parallelen Runde warten weiter auf die geprüfte Quittung (unverändert).

Abnahme: Unit-Tests mit Fake-Provider (Modell schneller als Quittung: Ausgabe startet vor `receipt green`; rot: Abbruch, Hinweis, kein external-Tool ausgeführt, Undo 1×), Mutationsbeleg; E2E wie WP81b (Overlay mit TEE-Fixture). Gate grün.
