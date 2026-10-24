# Wake-Prüfer B (zentrierter Vorlagen-Vergleich), Rechenvorschrift für den Dart-Nachbau

Stand WP137 (Stimmenset clean). Quelle: `tool/train_wake_word/verifier_eval.py` (`b_score`, `prep_templates`, `pick_templates`),
`verifier_data.py` (`segment`, `normalize`), `real_split.py` (`cut_clips`, `trim`). Paritätsdaten: `tool/train_wake_word/testdata/verifier_b_parity.json`
(synthetisch, erzeugt mit `verifier_export.py`), Mittelwert: `testdata/wake_verifier_b_mu.json`. Beide Wörter werden geprüft: Kopf W („Wendelin“) und Kopf HW („Hey Wendelin“).

## Rechenvorschrift
1. **Ausschnitt (live)**: Entscheidungs-Endsample `end` des Stufe-1-Fensters. `e = pyRound(end / 160) * 160`, `a = e - 30400` (1,9 s), `b = e + 13600` (0,85 s), Länge 44000.
   Außerhalb des Signals mit Nullen füllen. Spitze auf 0,5 normieren (`x * 0.5 / max|x|`, nur wenn `max|x| > 1e-6`, sonst unverändert).
   Dann Melspektrogramm und Embedding wie openWakeWord: auf Vielfache von 160 Samples kürzen, `M = n/160 - 3` Melspec-Frames, `F = (M - 76) / 8 + 1` Embedding-Frames (44000 Samples: F = 25). `M < 76`: ungültig.
   Ergebnis `emb` (F x 96), Feature-Version `oww-0.5.1-mel-emb-1`.
2. **Vorlagen** (Einlernen): je Wort Clips aus Label-Start/-Ende, Zuschnitt wie `real_split`, siehe „Zuschnitt“. Pro Clip: Spitze 0,5, ohne Stille-Polster, Melspec+Embedding, `m = F` Frames (m < 2 verwerfen).
   Training: 6 Vorlagen je Wort gleichmäßig über die sortierten Namen (`pick_templates`, Index `round(i*(n-1)/5)`); die App nimmt alle (gleichwertig), `TOPK = 3`.
3. **Zentrieren**: `mu` (96, Mittel über Trainings-Negativ-Ausschnitte) abziehen, jeden Frame auf Einheitsnorm (`v / (|v| + 1e-9)`), für Ausschnitt und Vorlagen.
4. **Wert je Vorlage**: Vorlage (m x 96) über den Ausschnitt schieben (Versatz `o = 0..F-m`); je Versatz Mittel über i der Kosinus `T[i] . E[o+i]`; Max über `o`.
   Vorlage mit `m > F` wird ignoriert. **Wert je Kopf** = Mittel der besten 3 Vorlagenwerte (bei weniger als 3: Mittel aller). Keine brauchbare Vorlage: -1.
5. **Schwellen** (Trainingsseite, Regel: niedrigste Schwelle mit Verwerfung >= `REJECT_MIN` der OOF-Negativen im Band): `ca1` W 0,6038, HW 0,6815. Annahme bei Wert >= Schwelle.

## Zuschnitt (Vorlagen, sample-genau, Rundung)
Label `start`/`ende` in Sekunden (double). `a = max(0, trunc((start - 0.12) * 16000))`, `b = min(len, trunc((ende + 0.20) * 16000))`; **abgeschnitten (Richtung 0), nicht gerundet**, im double gerechnet
(z. B. `(1.13 - 0.12) * 16000 = 16159,999...` gibt 16159). Danach `trim`: Frames zu 160 Samples, RMS je Frame, Frame zählt bei `20*log10(rms / (max_rms + 1e-9)) > -40`;
`lo = max(0, erster * 160 - 800)`, `hi = min(len, (letzter + 1) * 160 + 800)`; zählt kein Frame: ganzer Clip. Bei lauter Umgebung greift der Trim nicht (ganzer Zuschnitt).
Mindestlänge: `cut_clips` selbst nimmt Clips ab 4000 Samples, in den Prüfer kommt eine Vorlage aber erst ab 2 Embedding-Frames (`verifier_eval.build_templates`: `len(e) >= 2`), also ab 13920 Samples (ca. 0,87 s, `M = 84`, `F = 2`); kürzere Clips verwirft die App. Der Trim -40 dB kürzt keine der 29 echten Messvorlagen. Live-Ausschnitt: `pyRound` rundet Halbe zur geraden Zahl (500,5 -> 500, 501,5 -> 502), Dart `round()` rundet weg von null und weicht dort ab.
In der App gibt es keine Labels: Sprachgrenzen aus Pegel/VAD ersetzen Start/Ende; die Empfindlichkeit dafür ist nicht gemessen und offen.
Paritätsfälle dazu: `pcm.live` und `pcm.template` (Grenzen, Spitze, F bzw. m, ohne Embedding-Werte); `pcm.oww_frames_checked` sind an echtem openWakeWord gemessene Paare.

## Unterschied zum WP134-Vergleich (`wake_center_mean.g.dart`)
- WP134: ein flacher Vektor aus 16 x 96 Embeddings (Fenster), eigenes `mu`, ein Kosinus je Fenster.
- B: Folge aus F x 96 Frames, `mu` mit 96 Werten, Kosinus je Frame, Mittel über m, Max über den Versatz, Top-3-Mittel über Vorlagen.
- B nutzt den 2,75-s-Ausschnitt statt festem Fenster und andere Schwellen (je Kopf).

## Bekannte Grenzen
- B trennt „Wendelin“ nicht von „Hey Wendelin“ (Vorlagen beider Köpfe sind dem anderen Wort ähnlich).
- Schwelle unsicher: Auf der Trainingsseite nimmt sie nur etwa 4 % der Positiven an, im Prüf-Split etwa 60 %.
- Zu kurze Clips (unter 76 Melspec-Frames wirft die Python-Kette, unter 2 Embedding-Frames, also unter 13920 Samples bzw. ca. 0,87 s, nimmt der Prüfer keine Vorlage); die App muss sie ablehnen.

## Prüfung
`python verifier_export.py --models <ordner> --tag ca1` erzeugt beide Dateien neu (mit lokalen oww-Modellen zusätzlich `verifier_b_chain_parity.json`: Kettenfall mit echten Embeddings, Formel in der Datei); `test_verifier_export.py` rechnet die Parität neu (auch gegen die echten Funktionen `segment`, `trim`, `cut_clips`).
