# WP82 – GPU-Prüfung je Provider-Profil, Modelle immer wählbar mit Hinweis (`app/`, `wendelin_providers`)

Bezug: Nachtest APK 11193bb (2026-10-16, `ergebnisse.md`): (a) Die GPU-Prüfung (Aus/Vorher/Nachher) soll pro Provider-Profil im Provider-Reiter einstellbar sein, nicht global unter Datenschutz und Logs. (b) GLM 5.2 (Phala, kein GPU-Nachweis) steht in der Modellauswahl als „Modell nicht nutzbar“ und ist nicht wählbar. Gewünscht: jedes Modell wählbar, dahinter nur der Hinweis „keine GPU-Prüfung möglich (Anbieter liefert keinen Nachweis)“; die Profil-Einstellung entscheidet.

## Inhalt
1. **Einstellung je Profil:** `GpuCheckMode` wird Teil des Provider-Profils (Phala, NEAR, später Tinfoil). Migration: der bisherige globale Wert `tee.gpuCheck` wird für alle bestehenden TEE-Profile übernommen, danach entfernt. Abschnitt aus „Datenschutz und Logs“ in die Profil-Einstellungen verschieben (Texte aus `gpu_check_section.dart` wiederverwenden). Nicht-TEE-Profile zeigen den Abschnitt nicht.
2. **Modellauswahl:** Modelle ohne GPU-Nachweis bleiben wählbar, mit Hinweiszeile. „Modell nicht nutzbar“ nur noch bei echten Fehlern (Modell nicht erreichbar, Attestierung rot). Bei „Vorher“ und Modell ohne Nachweis: Anfrage wird nicht gesendet, Warnkarte mit Grund „kein Nachweis“ und Angebot „Ohne GPU-Prüfung senden“ (nur diese Anfrage) wie in WP77 vorgesehen; bei „Nachher“ Hinweis, nicht blockierend; bei „Aus“ nichts.
3. Die Einschränkungs-Bestätigung je Profil und Modell (WP78) nennt bei Modellen ohne GPU-Nachweis diese Einschränkung.

## Abnahmekriterien
- [ ] Tests: Migration, Einstellung je Profil wirkt nur auf dieses Profil, Modellauswahl-Widget (Hinweis statt gesperrt), Vorher-Fall mit „Ohne GPU-Prüfung senden“.
- [ ] Goldens aktualisiert (macOS). Prüfpunkte 12.9 in `docs/testing/m4-device.md` angepasst.
- [ ] Emulator (separater E2E-Agent) für betroffene Einstellungs-/TEE-Fixtures grün. Gate grün.
