# WP117 – Weitere deutsche Stimmen: Ramona, Eva, dii-high (`packages/wendelin_voice`)

**Zuordnung:** M5-Nachtest (Gerätetest 2026-10-20, T20-P.4). Wunsch Stefan 2026-10-21 nach Hörprobe: „Fügt bitte alle drei Stimmen schon mal hinzu“ (Ramona, Eva, dii-high), K86.

## Inhalt
Drei Katalogeinträge in `packages/wendelin_voice/lib/src/models/speech_model_catalog.dart` nach dem Muster von `voiceDeKerstin` (int8, sherpa-onnx-Release `tts-models`):

| id | Datei | Größe | sha256 (GitHub-Digest, beim Coder gegenprüfen) | Lizenz |
|---|---|---|---|---|
| `tts-de-ramona` | `vits-piper-de_DE-ramona-low-int8.tar.bz2` | 21199380 | `e532ddcbb09c16a65f56441bbbbf301083d2ea5b18ce937775303942f2b7a8f4` | Modellkarte Piper prüfen (laut Recherche CC0) |
| `tts-de-eva` | `vits-piper-de_DE-eva_k-x_low-int8.tar.bz2` | 13321491 | `0501123c7e184571a40690e79943f4111a57b988632f7f60a9d2344fd061e2a2` | Modellkarte Piper prüfen |
| `tts-de-dii` | `vits-piper-de_DE-dii-high-int8.tar.bz2` | 21030921 | `b0063594e9b5b210c08f4a3adf7a389f6ec6daa623604663708818591fa3ace3` | CC BY-NC-ND 4.0 (TigreGotico Lda, OpenVoiceOS); im Lizenz-/Hinweistext „nicht kommerziell“ deutlich nennen |

- Alle weiblich (`VoiceGender.female`), Sprache de, Anzeigename wie die übrigen („Deutsch – Ramona (weiblich)“ usw.; Qualität im Hinweis).
- Attribution je Stimme (Quelle der Daten, Modell, Lizenz); Links zu den Modellkarten.
- Lizenzliste/Third-Party-Hinweise im Repo ergänzen, falls es eine gibt (grep `kerstin` in `docs/`, `app/assets`).
- Bestehende Katalogtests (Anzahl, eindeutige IDs, Sprachen, Größen) anpassen.

## Abnahmekriterien
- [ ] Drei Einträge, Hashes gegen die heruntergeladenen Dateien geprüft (Notiz „SHA-256 selbst gehasht (Datum)“ wie bei Kerstin).
- [ ] Stimmen erscheinen in der App unter Sprache → Stimmen (Widget-/Katalogtest).
- [ ] Gate `--changed` grün, CI grün, Review FREIGABE.

## Parallel-Hinweise
- Berührt nur den Katalog und ggf. Lizenzdoku. WP115 (Entpacken) läuft parallel im selben Paket-Umfeld (`app/lib/platform/voice/`), keine Überschneidung.
