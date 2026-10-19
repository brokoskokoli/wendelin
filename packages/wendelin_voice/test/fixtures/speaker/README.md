# Synthetic speaker embeddings (WP92a)

`embeddings.json` holds 192-dimensional speaker embeddings (3D-Speaker CAM++,
`3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx`, rounded to 4
decimals) of **synthetic** voices. No recording of a real person is involved
and no audio is stored, only the vectors.

| Key | Voice (sherpa-onnx/Piper) | Dataset license |
| --- | --- | --- |
| `thorsten` | `de_DE-thorsten-high` | CC0 (Thorsten-Voice) |
| `kerstin` | `de_DE-kerstin-low` | CC0 (Rhasspy dataset-voice-kerstin) |
| `ljspeech` | `en_US-ljspeech-medium` | public domain (LJ Speech) |

Per voice 12 utterances (the list `de`/`en` in `gen_embeddings.py`, speed
1.0/0.95/1.05): the first 8 serve as enrollment, the last 4 as test
utterances. `sec` is the length of the utterance in seconds.

Regenerate: `python gen_embeddings.py out.json` with `sherpa_onnx` and `numpy`
installed and the two paths at the top set. Synthetic voices are far more
uniform than people: genuine scores are 0.7–0.95, strangers 0.0–0.15. The
thresholds in `SpeakerIdentifier` are therefore chosen conservatively and
must be checked with real voices on the device (`docs/testing/m5/wp92a.md`).
