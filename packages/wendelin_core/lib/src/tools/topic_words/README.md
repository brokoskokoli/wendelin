# Themenwörter je Sprache (WP119)

`de.dart`, `en.dart`, `fr.dart`: je Sprache eine Datei, Schlüssel = Integrations-ID
(alphabetisch), Wert = Wörter bzw. Wortanfänge, an denen eine Anfrage erkennbar
diese Integration braucht. Genutzt wird nur die Sprache der Anfrage bzw. des
Geräts (`topicWordsFor`): im `KeywordToolCategoryMatcher`, in der Suche
(`tools__search`) und beim Vorab-Freischalten der Tools.

## Regeln
- Wörter sind **Wortstämme** auf Wortgrenzen („notiz“ trifft „Notizen“); mehrere
  Wörter („weck mich“) müssen direkt hintereinander stehen. Groß/Klein und
  Akzente sind egal (`foldForMatch`: ä→a, é→e, ß→ss; Apostroph = Leerzeichen,
  also „qu est ce que“ für „qu’est-ce que“).
- Keine zu allgemeinen Wörter: Ein Treffer schaltet Tools frei (höchstens drei
  Integrationen je Anfrage).
- Jede Sprache führt **alle** Integrationen (Test `topic_words_test.dart`).

## Neue Sprache hinzufügen
1. Datei `<sprache>.dart` mit `const topicWords<Xx>` anlegen (Kopie von `en.dart`),
   in `topic_words.dart` unter `topicWordsByLanguage` eintragen.
2. Für jede Integration die Begriffe übersetzen **und** eigene Alternativen und
   umgangssprachliche Wörter der Sprache suchen, nicht nur 1:1 übersetzen
   (z. B. de „aufstehen“ für Wecker, fr „courses“ für Einkaufsliste; was sagt man
   wirklich, wenn man den Assistenten bittet?).
3. Test laufen lassen: Abdeckung aller Integrations-IDs wird geprüft.
