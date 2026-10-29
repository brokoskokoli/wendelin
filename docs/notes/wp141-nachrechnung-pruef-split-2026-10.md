# WP141 – Nachrechnung Prüf-Split (Wake-Halten bis 0,8 s)

Aus der Gerätetest-Anleitung [wp141.md](../testing/m5/wp141.md) ausgelagert (Messteil unverändert, Stand der Messung wie in den Abschnitten angegeben).

## Nachrechnung Prüf-Split (v8a, App-Bezug)
Band 0,98/0,999, Ausschnitt 2,0 s / 0,9 s um die Trefferzeit, hw2 normalisiert. Regel alt (5 Fenster, Abfall beendet das Halten) gegen neu (0,8 s). „Alt“ ist die Python-Nachbildung aus main, die beim ersten Abfall endet; die App auf main hatte `dropsToEnd` 2 (WP129). Der Bezug ist also nicht genau die alte App, daher der Versatz „19× −0,08 s“ unten. Huawei B4–6 und handy2 B1–6 sind dieselbe Sitzung auf zwei Geräten, also nicht unabhängig.

| Gerät | Wort | Treffer alt | Treffer neu | direkt alt → neu | Stufe 2 bestanden alt → neu |
|---|---|---|---|---|---|
| huawei | Wendelin | 11/15 | 11/15 | 5 → 7 | 6/8 → 4/6 |
| huawei | Hey Wendelin | 12/15 | 14/15 | 10 → 11 | 2/4 → 3/3 |
| handy2 | Wendelin | 21/30 | 21/30 | 8 → 12 | 13/15 → 9/11 |
| handy2 | Hey Wendelin | 22/30 | 20/30 | 15 → 16 | 7/12 → 4/11 |

- Treffer gesamt 66/90 → 66/90, Direktannahmen 38 → 46 (8 Rufe brauchen Stufe 2 nicht mehr, davon 7 vorher bestanden). 2 Rufe fallen neu durch (handy2 Hey Wendelin): Der Ausschnitt liegt 0,08 s früher bzw. 0,32 s später, und das hw2-Transkript kippt. 1 Ruf besteht neu (Huawei Hey Wendelin). Bei 15–30 Rufen je Zelle (Wilson ±15–25 Punkte) ist keiner der Unterschiede belastbar.
- Ausschnitt neu − alt (77 Rufe mit Ereignis in beiden): 19× −0,08 s, 40× gleich, 18× später (bis +0,40 s).
- Verwechsler (300 Clips): Ereignisse 23 → 23, davon direkt 2 → 2, durchkommend Wendelin 5 → 5, Hey Wendelin 4 → 4. Negativquellen (neg_huawei, neg_handy2, syn, fleurs): unverändert, FA/h 0 / 0 / 0,52 / 0,99 bei je 0–1 Ereignis.
- Messaufbau: Bei einem kurzen Clip, der während des Haltens endet, entscheidet die Nachbildung am Kurvenende mit der Spitze (`flush`), so wie die App bei weiterlaufendem Strom. Ohne das fehlten 8 Verwechsler-Ereignisse und 1 syn-Ereignis, und die neue Regel sah scheinbar besser aus.
