# WP74 – Kleinigkeiten Sprache (`app/`)

Bezug: Gerätetest 2026-10-15, `ergebnisse.md` Prio 3 Nr. 9–11, 15.

## Inhalt
1. „Hört noch 5 s zu · „Stopp“ beendet“ steht dauerhaft unten, auch ohne Zuhören; nach dem Herunterzählen springt die Zeile auf 5 s zurück. Soll nur während des echten Folgefensters sichtbar sein und danach verschwinden.
2. „Probe hören“: sofort sichtbare Rückmeldung (Ladezeichen/„Wird vorbereitet …“) während der ~1,5–2 s bis zur Probe.
3. „Probe hören“ nicht unter jeder Sprache: ein Knopf je Stimmenzeile (Abspielsymbol an der gewählten/jeweiligen Stimme) oder ein gemeinsamer Knopf – schlank, wie im Design.
4. Leichtes Rauschen aller Offline-Stimmen: prüfen, ob Parameter (`noise_scale`, `noise_scale_w`, `length_scale`, Lautstärke/Clipping, Resampling) das Rauschen verursachen; sinnvolle Werte setzen, wenn belegbar (Vergleich per Spektrum/RMS der Stille-Anteile im Test).

## Abnahmekriterien
- [ ] Widget-Tests/Goldens für 1–3; für 4 ein Test der Parameter und eine Messung im Bericht.
- [ ] Gate grün.

## Umsetzung

- Punkt 2/3: Abspielknopf je Stimmenzeile mit Linien-Icons `WIcons.play`/`WIcons.stop` (`WIconButton`). Ablauf: Ladezeichen „Probe wird vorbereitet …“ bis die Ausgabe `speaking` meldet, dann Stopp-Symbol (Antippen bricht ab), danach wieder Abspielen. Fehler zeigen eine Snackbar.
- Punkt 4 (Rauschen), Messung: In den Pausen der Piper-Stimmen liegt das Rauschen bei int8 etwa −65 dBFS, bei fp32 etwa −80 dBFS. Die Parameter `noise_scale`, `noise_scale_w` und `length_scale` ändern das Pausenrauschen um höchstens 1,5 dB. Ursache sind also die int8-Modelle, nicht die Parameter; diese bleiben bewusst auf den sherpa-Standardwerten (0,667 / 0,8 / 1,0). Festgehalten in `sherpaTtsConfig` (`app/lib/platform/voice/sherpa_tts.dart`) und im Test `app/test/platform/voice/tts_test.dart`.
