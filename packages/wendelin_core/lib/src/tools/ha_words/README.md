# Smart-Home-Wörter je Sprache (WP135)

`de.dart`, `en.dart`, `fr.dart`: je Sprache Gerätetypen (Wortstämme je
Home-Assistant-Domain: `light`, `cover`, `switch`, `climate`), Aktionswörter
(`HaAction`: an, aus, öffnen, schließen, stoppen, heller, dunkler, halb),
Prozent- und Gradwörter sowie typische Verhörer der Spracherkennung
(`recognitionErrors`, z. B. de „Rolle“ für „Rollo“).

## Sperrwörter
`blockers` je Sprache: Wortstämme (Garage, Tor, Tür, Schloss, Alarm …), die den Schnellweg für jedes Gerät sperren, dessen Name oder Entity-Id sie enthält, in jeder Domain. Es zählen die Listen **aller** Sprachen. `^` vorn = Wortanfang (`^tur` trifft nicht „Temperatur“, `^tor` nicht „Ventilator“). Im Zweifel sperren (Modell entscheidet).

## Regeln
- Typen sind **Wortstämme** (Wortanfang, „lampe“ trifft „Lampen“), Aktionen
  **ganze Wörter** oder Wortfolgen („an“ darf nicht in „Anhalter“ treffen).
  Groß/Klein und Akzente sind egal (`foldForMatch`).
- Pro Sprache eigene, umgangssprachliche Wörter suchen, nicht 1:1 übersetzen
  (Rollo: „rauf/hoch/auf“, „runter/zu“; fr „monte“, „descends“).
- Jede Sprache führt **jede** Domain und **jede** Aktion (Test
  `ha_words_test.dart`).
- Einziger Aufrufer für Typ und Aktion: `haDomainsIn` / `haActionsIn`.
  Die Geräte-Auflösung (`HaContext.resolve`), die Vorauswahl (Themenwörter,
  `haTypeStems<Sprache>`) und der Schnellweg (WP135 D) nutzen diese Listen.
- Mehrdeutige Wörter („auf“ = öffnen oder „auf 50 %“, „ein“) löst der
  Aufrufer: bei mehreren Treffern von `haActionsIn` ist der Satz unklar.

## Neue Sprache
Datei kopieren (`en.dart`), in `ha_words.dart` unter `haWordsByLanguage` und
`haTopicExtraByLanguage` eintragen, Test laufen lassen.
