# Hotword-Bias bei Parakeet (WP146, 2026-10-25)

Frage: Erkennt Parakeet nach dem Weckwort ständig Kontaktnamen, weil die Hotwords (Bonus 3,0, `modified_beam_search`) bei schlechtem Audio dominieren? Gemessen, nichts geändert.

## Aufbau

- Werkzeug: `tool/voice_quality_measure.py hotword-bias` und `hotword-bias-wake` (Python-venv `$WENDELIN_FIXTURES/venv`, sherpa-onnx 1.13.8 wie die App, Parakeet-v3 int8, 4 Threads, Standard-`max_active_paths`).
- 300 erfundene Namen (Vor- plus Nachname aus zufälligen Silben, feste Seed 146, keine echten Personen), dazu 5 erfundene Listennamen und „Wendelin“. Die Teilmengen 0/50/300 enthalten immer „Wendelin“ und die Listennamen; die 10 gesprochenen Namen stehen in jeder Teilmenge mit n>0 (Recall ist dadurch günstig).
- Audio: 12 de-Fixtures ohne Namen (`app/test/fixtures/stt`), 10 `say`-Befehle mit je einem erfundenen Namen. Wake-Pfad: je Befehl `say` „Hey Wendelin, …“ (ohne Pause) und „Hey Wendelin. [[slnc 500]] …“ (mit Pause), dazu der Befehl allein (Tipp-Pfad). 20 Befehle.
- Bedingungen: clean, noisy 10 dB, Handoff-Loch (600 ms auf null, mittig im ersten Wort), Handoff-Schnitt (Beginn mitten im ersten Wort), nur Stille, nur Rauschen. Wake-Pfad: Schnitt bei Wortende „Wendelin“ mit Versatz -400/-200/0/+200 ms (Ende bei Pause aus der Energie, ohne Pause aus separat gerendertem „Hey Wendelin,“), zusätzlich Loch (erste 9600 Samples nach dem Schnitt null) und Mute (erste 3200 Samples null, nur mit Pause). Mit Pause werden Segment bis zur Pause und Rest getrennt decodiert, Transkripte verbunden.
- Metriken: WER (Bootstrap-95%-Intervall über Äußerungen), Einfügungsrate = Anteil Äußerungen, deren Transkript ein Namenswort (Vor-/Nachname, Listenname) enthält, das nicht in der Referenz steht (Wilson-95%-Intervall in %), Recall = gesagte Namensteile im Transkript.
- Konfigurationen: `greedy` (App ohne Hotwords), `beam` (modified_beam_search ohne Hotwords), `hwN sB` = N erfundene Kontakte, Bonus B.

## Ergebnis Wake-Pfad (Namen eingefügt, nicht gesagt)

| Konfiguration | Tipp-Pfad clean | Tipp-Pfad noisy | Wake ohne Pause, Schnitt, clean | Wake ohne Pause, Schnitt, noisy | Wake mit Pause, Schnitt, clean | Wake mit Pause, Schnitt, noisy | Pause + Mute | Loch 600 ms (beide Pfade) |
|---|--:|--:|--:|--:|--:|--:|--:|--:|
| beam | 0% (0/20; 0-16) | 0% (0/20; 0-16) | 0% (0/80; 0-5) | 0% (0/80; 0-5) | 0% (0/80; 0-5) | 0% (0/80; 0-5) | 0% (0/160; 0-2) | 0% (0/320; 0-1) |
| hw0 s1.5 | 0% (0/20; 0-16) | 0% (0/20; 0-16) | 0% (0/80; 0-5) | 0% (0/80; 0-5) | 0% (0/80; 0-5) | 0% (0/80; 0-5) | 0% (0/160; 0-2) | 0% (0/320; 0-1) |
| hw0 s3.0 | 0% (0/20; 0-16) | 0% (0/20; 0-16) | 0% (0/80; 0-5) | 0% (0/80; 0-5) | 0% (0/80; 0-5) | 0% (0/80; 0-5) | 0% (0/160; 0-2) | 0% (0/320; 0-1) |
| hw50 s1.5 | 0% (0/20; 0-16) | 0% (0/20; 0-16) | 0% (0/80; 0-5) | 0% (0/80; 0-5) | 0% (0/80; 0-5) | 0% (0/80; 0-5) | 0% (0/160; 0-2) | 0% (0/320; 0-1) |
| hw50 s3.0 | 0% (0/20; 0-16) | 0% (0/20; 0-16) | 0% (0/80; 0-5) | 0% (0/80; 0-5) | 0% (0/80; 0-5) | 5% (4/80; 2-12) | 2% (4/160; 1-6) | 2% (5/320; 1-4) |
| hw300 s1.5 | 0% (0/20; 0-16) | 0% (0/20; 0-16) | 0% (0/80; 0-5) | 0% (0/80; 0-5) | 0% (0/80; 0-5) | 0% (0/80; 0-5) | 0% (0/160; 0-2) | 0% (0/320; 0-1) |
| hw300 s3.0 | 10% (2/20; 3-30) | 15% (3/20; 5-36) | 4% (3/80; 1-10) | 10% (8/80; 5-19) | 5% (4/80; 2-12) | 18% (14/80; 11-27) | 8% (12/160; 4-13) | 9% (29/320; 6-13) |

Je Schnittversatz (Wake mit Pause bzw. ohne Pause, plain, clean+noisy), nur hw300 s3.0 und beam:

| Konfiguration | Pfad | -400 | -200 | 0 | +200 |
|---|---|--:|--:|--:|--:|
| beam | np | 0% (0/40; 0-9) | 0% (0/40; 0-9) | 0% (0/40; 0-9) | 0% (0/40; 0-9) |
| beam | p | 0% (0/40; 0-9) | 0% (0/40; 0-9) | 0% (0/40; 0-9) | 0% (0/40; 0-9) |
| hw300 s3.0 | np | 2% (1/40; 0-13) | 8% (3/40; 3-20) | 8% (3/40; 3-20) | 10% (4/40; 4-23) |
| hw300 s3.0 | p | 10% (4/40; 4-23) | 20% (8/40; 10-35) | 8% (3/40; 3-20) | 8% (3/40; 3-20) |

## Ergebnis Einzelbedingungen (22 Äußerungen je Bedingung, noisy 66)

**clean**: WER ohne Namen / mit Namen (95%-Bootstrap), Einfügungsrate erfundener Namen, Recall gesagter Namen

| Konfiguration | WER ohne Namen | WER mit Namen | Namen eingefügt | Recall |
|---|--:|--:|--:|--:|
| greedy | 3.9 (0-9) | 52.5 (40-66) | 0% (0/22; 0-15) | 0/20 |
| beam | 3.9 (0-9) | 52.5 (41-66) | 0% (0/22; 0-15) | 0/20 |
| hw300 s1.0 | 3.9 (0-9) | 47.5 (36-62) | 0% (0/22; 0-15) | 2/20 |
| hw300 s1.5 | 3.9 (0-9) | 42.6 (30-58) | 0% (0/22; 0-15) | 4/20 |
| hw300 s2.0 | 3.9 (0-9) | 42.6 (27-59) | 0% (0/22; 0-15) | 6/20 |
| hw300 s3.0 | 10.5 (4-19) | 44.3 (29-61) | 5% (1/22; 1-22) | 7/20 |
| hw0 s1.5 | 5.3 (1-11) | 50.8 (39-64) | 0% (0/22; 0-15) | 0/20 |
| hw50 s1.5 | 3.9 (0-9) | 36.1 (23-48) | 0% (0/22; 0-15) | 6/20 |
| hw0 s3.0 | 5.3 (1-11) | 50.8 (40-62) | 0% (0/22; 0-15) | 0/20 |
| hw50 s3.0 | 11.8 (2-26) | 34.4 (22-47) | 0% (0/22; 0-15) | 7/20 |

**noisy 10 dB (3 Seeds)**: WER ohne Namen / mit Namen (95%-Bootstrap), Einfügungsrate erfundener Namen, Recall gesagter Namen

| Konfiguration | WER ohne Namen | WER mit Namen | Namen eingefügt | Recall |
|---|--:|--:|--:|--:|
| greedy | 32.0 (20-47) | 76.0 (63-89) | 0% (0/66; 0-6) | 1/60 |
| beam | 31.6 (20-45) | 71.0 (60-82) | 0% (0/66; 0-6) | 0/60 |
| hw300 s1.0 | 32.5 (21-45) | 73.2 (62-85) | 0% (0/66; 0-6) | 1/60 |
| hw300 s1.5 | 33.3 (21-47) | 71.0 (60-84) | 0% (0/66; 0-6) | 4/60 |
| hw300 s2.0 | 32.5 (21-45) | 72.7 (61-84) | 0% (0/66; 0-6) | 6/60 |
| hw300 s3.0 | 44.7 (33-60) | 73.8 (63-84) | 5% (3/66; 2-13) | 6/60 |
| hw0 s1.5 | 32.9 (21-47) | 73.2 (62-85) | 0% (0/66; 0-6) | 0/60 |
| hw50 s1.5 | 34.2 (22-49) | 72.7 (61-84) | 0% (0/66; 0-6) | 4/60 |
| hw0 s3.0 | 35.1 (23-49) | 73.2 (62-85) | 6% (4/66; 2-15) | 0/60 |
| hw50 s3.0 | 38.6 (28-51) | 71.6 (61-82) | 2% (1/66; 0-8) | 8/60 |

**Handoff-Loch 600 ms**: WER ohne Namen / mit Namen (95%-Bootstrap), Einfügungsrate erfundener Namen, Recall gesagter Namen

| Konfiguration | WER ohne Namen | WER mit Namen | Namen eingefügt | Recall |
|---|--:|--:|--:|--:|
| greedy | 40.8 (26-61) | 73.8 (57-90) | 0% (0/22; 0-15) | 0/20 |
| beam | 47.4 (29-72) | 73.8 (57-90) | 0% (0/22; 0-15) | 0/20 |
| hw300 s1.0 | 40.8 (26-61) | 77.0 (58-93) | 0% (0/22; 0-15) | 0/20 |
| hw300 s1.5 | 42.1 (27-62) | 72.1 (55-90) | 0% (0/22; 0-15) | 2/20 |
| hw300 s2.0 | 43.4 (27-65) | 73.8 (57-93) | 0% (0/22; 0-15) | 2/20 |
| hw300 s3.0 | 47.4 (31-68) | 72.1 (56-90) | 0% (0/22; 0-15) | 2/20 |
| hw0 s1.5 | 48.7 (29-75) | 72.1 (56-87) | 0% (0/22; 0-15) | 0/20 |
| hw50 s1.5 | 48.7 (30-72) | 72.1 (55-91) | 0% (0/22; 0-15) | 2/20 |
| hw0 s3.0 | 48.7 (30-73) | 73.8 (57-90) | 0% (0/22; 0-15) | 0/20 |
| hw50 s3.0 | 46.1 (29-68) | 70.5 (48-93) | 5% (1/22; 1-22) | 4/20 |

**Handoff-Schnitt**: WER ohne Namen / mit Namen (95%-Bootstrap), Einfügungsrate erfundener Namen, Recall gesagter Namen

| Konfiguration | WER ohne Namen | WER mit Namen | Namen eingefügt | Recall |
|---|--:|--:|--:|--:|
| greedy | 25.0 (12-43) | 63.9 (51-81) | 0% (0/22; 0-15) | 0/20 |
| beam | 25.0 (12-43) | 63.9 (51-81) | 0% (0/22; 0-15) | 0/20 |
| hw300 s1.0 | 25.0 (12-43) | 63.9 (49-80) | 0% (0/22; 0-15) | 2/20 |
| hw300 s1.5 | 25.0 (12-43) | 67.2 (47-90) | 0% (0/22; 0-15) | 3/20 |
| hw300 s2.0 | 25.0 (12-45) | 68.9 (47-96) | 0% (0/22; 0-15) | 3/20 |
| hw300 s3.0 | 26.3 (12-45) | 65.6 (48-84) | 14% (3/22; 5-33) | 5/20 |
| hw0 s1.5 | 26.3 (12-46) | 70.5 (55-88) | 0% (0/22; 0-15) | 0/20 |
| hw50 s1.5 | 25.0 (12-43) | 62.3 (46-80) | 0% (0/22; 0-15) | 3/20 |
| hw0 s3.0 | 26.3 (12-45) | 65.6 (53-79) | 5% (1/22; 1-22) | 0/20 |
| hw50 s3.0 | 28.9 (13-50) | 68.9 (47-96) | 0% (0/22; 0-15) | 5/20 |

**Nur Stille / nur Rauschen** (3 s): Anteil Läufe mit nicht leerem Transkript / mit eingefügtem Namen

| Konfiguration | Stille | Rauschen -40 dB | Rauschen -26 dB |
|---|--:|--:|--:|
| greedy | 0/1 / 0/1 | 0/20 / 0/20 | 0/20 / 0/20 |
| beam | 0/1 / 0/1 | 5/20 / 0/20 | 2/20 / 0/20 |
| hw300 s1.0 | 0/1 / 0/1 | 2/20 / 0/20 | 2/20 / 0/20 |
| hw300 s1.5 | 0/1 / 0/1 | 1/20 / 0/20 | 1/20 / 0/20 |
| hw300 s2.0 | 0/1 / 0/1 | 3/20 / 0/20 | 1/20 / 0/20 |
| hw300 s3.0 | 1/1 / 0/1 | 20/20 / 3/20 | 19/20 / 4/20 |
| hw0 s1.5 | 0/1 / 0/1 | 2/20 / 0/20 | 2/20 / 0/20 |
| hw50 s1.5 | 0/1 / 0/1 | 2/20 / 0/20 | 1/20 / 0/20 |
| hw0 s3.0 | 0/1 / 0/1 | 9/20 / 0/20 | 9/20 / 0/20 |
| hw50 s3.0 | 0/1 / 0/1 | 17/20 / 0/20 | 18/20 / 0/20 |

## Nachmessung Wake-Pfad mit Bonus 0,5 / 1,0 / 1,5 (Review Runde 2)

Frage: Erkennt der gewählte Bonus 1,0 Reste des Weckworts (Schnittversatz -400/-200/0/+200 ms) seltener als „Wendelin“, sodass `stripWakeWord` nicht greift? Aufruf: `hotword-bias-wake --counts 300 --scores 0.5,1.0,1.5` (beam immer dabei), gleiche Fixtures wie oben, 20 Befehle, je Zelle n = 40. Die Tabelle „Weckwort erkannt“ ergänzt das Werkzeug; das echte `stripWakeWord` lief auf den gespeicherten Transkripten (Wake plain, clean + noisy).

- Eingefügte Namen: 0 % in allen Spalten für beam, s0,5, s1,0, s1,5 (je 0/20 bis 0/320).
- „Wendelin“ wörtlich im Transkript: 0/40 in jeder Zelle, auch ohne Hotwords (beam). `stripWakeWord` greift in 0/320 je Konfiguration, ebenfalls gleich zu beam.
- Deutung: Der Bonus ändert hier nichts, weil nach dem Schnitt kein vollständiges Wort mehr im Audio liegt. Bei -400 ms bleibt ein Bruchstück („Dillin“, „Silling“, „The Lynn“, „Silent“; Abstand zu „wendelin“ 3 oder mehr), bei -200 ms und später nichts. Mit Pause steht stattdessen ein Füllwort („Mm.“, „Then.“) als eigener Satz vor dem Befehl. Beides bleibt mit `stripWakeWord` stehen, mit beam genauso wie mit 1,0. Das Risiko liegt damit am Schnittpunkt der Übergabe, nicht am Bonus; ob es am Gerät auftritt, zeigen `relisten reason=wake-only` und der Text vor dem Befehl (offen, Gerätebeleg).
- Plausibilität: Die Nullrate für „Wendelin“ ist kein Fehler des Bonus, sondern folgt aus dem Versuchsaufbau (Wort geschnitten). Sie sagt nichts darüber, wie oft ein vollständig erhaltenes Weckwort erkannt wird (dort wirkt der Bonus, siehe Sanity-Zeile in `wake-word-station-spike.md`). Synthetische Stimmen, n = 40 je Zelle (Wilson-Obergrenze bei 0/40: 9 %).

## Deutung

- Ohne Hotwords (greedy und beam) erscheint in keiner Bedingung ein Listenname; bei Stille und Rauschen bleibt greedy leer. Die Beam-Suche selbst ist nicht die Ursache: gleiche WER wie greedy, nur leicht mehr Leerausgaben bei Rauschen.
- Bonus 1,0 bis 2,0 mit 300 Namen: keine eingefügten Namen, WER ohne Namen unverändert (3,9 % clean). Bonus 3,0 mit 300 Namen: WER ohne Namen clean 10,5 % statt 3,9 %, noisy 44,7 % statt 32 %, Einfügungen 4 bis 18 % je Wake-Szenario (mit Pause, noisy 18 %); in reinem Rauschen liefert er in 19 bis 20 von 20 Läufen Text (z. B. „Welcome to Holy Got“).
- Namenszahl bei Bonus 3,0: 0 Kontakte keine Einfügungen im Wake-Pfad, 50 rund 2 %, 300 bis 18 %. Bei Bonus 1,5 bleibt es mit 300 Namen bei 0 Einfügungen.
- Gesprochene Namen werden auch mit Hotwords schlecht erkannt (Recall clean höchstens 7/20). Bonus 1,5 bis 2,0 bringt den größten Teil des Nutzens (4 bis 6/20 gegen 0/20), 3,0 wenig mehr.
- Teilwort-Halluzinationen („Holy Sol“, „Solid Sol“) sind Namensbruchstücke. Die Einfügungsrate zählt nur ganze Namenswörter und unterschätzt sie; die Rate nicht leerer Transkripte bei Rauschen ist die ehrlichere Zahl.

## Zweifel

- Synthetische `say`-Stimmen, 20 bis 22 Befehle: breite Intervalle, Echtstimmen können abweichen. Rauschen ist synthetisch, kein Raumklang.
- Erfundene Namen klingen in der TTS wie Fremdwörter; der Recall ist nicht übertragbar.
- bpe.vocab ist das Original-SentencePiece-Vocab, die App leitet es aus `tokens.txt` ab (laut Kommentar gleich, nicht gegengeprüft).
- Wortende „Wendelin“ ohne Pause ist aus einer getrennt gerenderten Vorlage geschätzt (Prosodie kann abweichen); das Loch ersetzt Audio durch Null, fügt keine Stille ein.
- Namenszählung nur auf Wortebene (Bruchstücke fehlen).
