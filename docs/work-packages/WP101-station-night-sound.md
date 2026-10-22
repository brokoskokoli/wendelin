# WP101 – Stationsmodus: Ruhezeiten, Bluetooth-Lautsprecher, Wecker mit Ansage (`app/`, Android)

**Zuordnung:** M6. Nach WP99.

Bezug: Konzept Stationsmodus; K62, K63.

## Inhalt
1. **Ruhezeiten (Ton):** in den einstellbaren Ruhezeiten (WP99) leiser antworten, kein Bestätigungston, Display fast schwarz.
2. **Bluetooth-Lautsprecher:** Antworten und Musik über einen gekoppelten Lautsprecher, wenn verbunden; sonst Handy-Lautsprecher. Auswahl des Lautsprechers in den Einstellungen.
3. **Wecker mit Ansage:** Klingelt ein Wecker bei laufender Station, sagt Wendelin nach dem Ausschalten Wetter, Termine und fällige Aufgaben des Tages an (mit Titeln, K62). Erkennung des Weckers über die Wecker-Integration bzw. `AlarmManager`-Broadcast; nur Wecker, die Wendelin selbst gestellt hat, wenn andere nicht erkennbar sind (als Abweichung melden).

## Umsetzung
- Lautstärke und Audioziel über einen Port, testbar mit Fake.
- Parallel: WP100 (berührt Gesprächsansicht und Policy, nicht Ton/Wecker).

## Abnahmekriterien
- [ ] Tests: Ruhezeit-Grenzen (virtuelle Uhr, Mitternacht), Audioziel-Wechsel bei Verbinden/Trennen, Inhalt der Wecker-Ansage.
- [ ] E2E (Emulator): Ruhezeit-Verhalten, Wecker-Ansage nach Test-Wecker. Bluetooth nur im Gerätetest (Maintainer). Gate grün.
