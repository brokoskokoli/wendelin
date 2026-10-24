# Wake-Prüfer B (zentrierter Vorlagen-Vergleich), Rechenvorschrift für den Dart-Nachbau

Stand WP137 (Stimmenset clean). **Datenleck behoben (2026-10-24):** Alle bis 2026-10-24 gemeldeten WP137-Zahlen enthielten das zweite Handy Block 1 bis 3, das dieselben gesprochenen Rufe wie die Trainingsaufnahme huawei Block 1 bis 3 trägt (gleiche Sitzung, fester Geräteversatz); der Prüf-Split ist nun huawei und zweites Handy Block 4 bis 6 (`real_split.paired_sessions`, `v8_measure.filter_labels`). **Messstand:** Die gemessenen Prüfer-Zahlen (Schwellen, Split-Ergebnisse) stammen von der alten Ereignisregel (Entscheidungsfenster der App, Halten höchstens 5 Fenster). Ab WP141 hält `stage2_cut.app_events` zeitbasiert bis 0,8 s und liefert als Zeit das Spitzenfenster; der Live-Ausschnitt liegt damit um das Spitzenfenster. Training und Prüfung (`verifier_data.stream_events`) folgen der neuen Regel, neu gemessen wurde nicht. Auch das zweite Handy Block 4 bis 6 und die Negativaufnahmen sind dieselbe Sitzung wie Huawei (Versatz etwa 0,72 s): Die 60 Prüf-Labels sind 30 Rufe mit je 2 Mikrofonen, und FA/h „echt“ über neg_huawei und neg_handy2 zählt dieselbe Zeit doppelt (nur dokumentiert, Messlogik unverändert). Eine Versatzprobe von ±0,16 s zeigte bei B kaum Wirkung. Quelle: `tool/train_wake_word/verifier_eval.py` (`b_score`, `prep_templates`, `pick_templates`),
`verifier_data.py` (`segment`, `normalize`), `real_split.py` (`cut_clips`, `trim`). Paritätsdaten: `tool/train_wake_word/testdata/verifier_b_parity.json`
(synthetisch, erzeugt mit `verifier_export.py`), Mittelwert: `testdata/wake_verifier_b_mu.json`. Beide Wörter werden geprüft: Kopf W („Wendelin“) und Kopf HW („Hey Wendelin“).

## Rechenvorschrift
1. **Ausschnitt (live)**: Spitzen-Endsample `end` des Spitzenfensters der App-Regel (WP141; die unten genannten gemessenen Zahlen stammen noch von der alten Entscheidungsfenster-Regel). `e = pyRound(end / 160) * 160`, `a = e - 30400` (1,9 s), `b = e + 13600` (0,85 s), Länge 44000.
   Außerhalb des Signals mit Nullen füllen. Spitze auf 0,5 normieren (float32: `x * f32(0.5 / max|x|)`, nur wenn `max|x| > 1e-6`, sonst unverändert; `x*0.5/m` in double weicht um höchstens 1 ulp ab, für die Toleranz 1e-4 ohne Wirkung, aber nicht bitgleich).
   **float → int16** vor dem Melspektrogramm: `trunc(x * 32767)` (Python `astype("int16")`, `common.embed`), abgeschnitten, nicht gerundet. Die App-Hilfe `floatToPcm` (`app/lib/platform/voice/pcm.dart`) rundet dagegen; für einen bitgenauen Nachbau muss die App-Seite auf Abschneiden angepasst werden (Abweichung höchstens 1 LSB, Folge für die Embedding-Werte nicht gemessen; die Kettenparität prüft mit Toleranz 1e-3).
   Zeitraster: `end` liegt in der Messung auf `1280*k - 3360` Samples (`common.window_end`), also nie auf einem Halbwert von `end / 160`; die Echt-`segment` rechnet mit `te` in Sekunden (`round(te*16000/160)`), `pyRound(end/160)` weicht davon nur bei Halbwerten ab (z. B. `end` 16240). Diese Fälle kommen im Strom nicht vor; die Paritätsfälle `halbe_*` prüfen die Regel trotzdem.
   Dann Melspektrogramm und Embedding wie openWakeWord: auf Vielfache von 160 Samples kürzen, `M = n/160 - 3` Melspec-Frames, `F = (M - 76) / 8 + 1` Embedding-Frames (44000 Samples: F = 25). `M < 76`: ungültig.
   Ergebnis `emb` (F x 96), Feature-Version `oww-0.5.1-mel-emb-1`.
2. **Vorlagen** (Einlernen): je Wort Clips aus Label-Start/-Ende, Zuschnitt wie `real_split`, siehe „Zuschnitt“. Pro Clip: Spitze 0,5, ohne Stille-Polster, Melspec+Embedding, `m = F` Frames (m < 2 verwerfen). **Höchstlänge:** Training und Messung laden die Clips mit `load_wavs(real_pos, None, 2.2)` (`verifier_eval.py` phase_fit, `verifier_data.py` load_wavs) und verwerfen alles über 35200 Samples (2,2 s, `m > 18`) vor `pick_templates`; gemessen wurde nur mit `m <= 18` (tatsächlich `m = 2..6`). Eine längere Vorlage ist nicht gemessen; die App sollte sie ablehnen (Paritätsfeld `rule.template`).
   Training: 6 Vorlagen je Wort gleichmäßig über die sortierten Namen (`pick_templates`, Index `round(i*(n-1)/5)`); die App nimmt alle (gleichwertig), `TOPK = 3`.
3. **Zentrieren**: `mu` (96, Mittel über Trainings-Negativ-Ausschnitte) abziehen, jeden Frame auf Einheitsnorm (`v / (|v| + 1e-9)`), für Ausschnitt und Vorlagen.
4. **Wert je Vorlage**: Vorlage (m x 96) über den Ausschnitt schieben (Versatz `o = 0..F-m`); je Versatz Mittel über i der Kosinus `T[i] . E[o+i]`; Max über `o`.
   Vorlage mit `m > F` wird ignoriert. **Wert je Kopf** = Mittel der besten 3 Vorlagenwerte (bei weniger als 3: Mittel aller; die Paritätsfälle `top3_aus_6_vorlagen` und der Kettenfall mit 5 Vorlagen prüfen die Auswahl). Keine brauchbare Vorlage: -1.
5. **Schwellen** (Trainingsseite, Regel: niedrigste Schwelle mit Verwerfung >= `REJECT_MIN` der OOF-Negativen im Band): `ca1` W 0,6038, HW 0,6815. Annahme bei Wert >= Schwelle.

## Zuschnitt (Vorlagen, sample-genau, Rundung)
Label `start`/`ende` in Sekunden (double). `a = max(0, trunc((start - 0.12) * 16000))`, `b = min(len, trunc((ende + 0.20) * 16000))`; **abgeschnitten (Richtung 0), nicht gerundet**, im double gerechnet
(z. B. `(1.13 - 0.12) * 16000 = 16159,999...` gibt 16159). Danach `trim`: Frames zu 160 Samples, RMS je Frame, Frame zählt bei `20*log10(rms / (max_rms + 1e-9)) > -40`;
`lo = max(0, erster * 160 - 800)`, `hi = min(len, (letzter + 1) * 160 + 800)`; zählt kein Frame: ganzer Clip. Bei lauter Umgebung greift der Trim nicht (ganzer Zuschnitt).
Mindestlänge: `cut_clips` selbst nimmt Clips ab 4000 Samples (`accepted_by_cut_clips`), in den Prüfer kommt eine Vorlage aber erst ab 2 Embedding-Frames (`verifier_eval.build_templates`: `len(e) >= 2`; Feld `usable_as_template`), also ab 13920 Samples (ca. 0,87 s, `M = 84`, `F = 2`; 13919 Samples geben `F = 1` und werden verworfen, Fälle `grenze_13919`/`grenze_13920`); kürzere Clips verwirft die App. Der Trim -40 dB kürzt keinen der 29 Clips des Trainings-Satzes (`real_pos`): erneutes Trim ändert keine Länge (kürzester 13760, längster 27199 Samples). Daraus wählt `pick_templates` 6 je Wort, das ergibt die 12 Vorlagen in `b_templates.npz` (`m = 2..6`); die Zahl 29 sind Clips, nicht Vorlagen. Der kürzeste Clip (13760 Samples) läge unter 13920 und wäre als Vorlage verworfen worden, ist aber nicht unter den gewählten. Live-Ausschnitt: `pyRound` rundet Halbe zur geraden Zahl (500,5 -> 500, 501,5 -> 502), Dart `round()` rundet weg von null und weicht dort ab.
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
