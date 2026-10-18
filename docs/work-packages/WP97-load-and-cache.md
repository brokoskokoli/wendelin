# WP97 – Lastbremse und Build-Cache (`tool/gate.dart`, `tool/src/gate_rust.dart`, `tool/build_attest_android.sh`)

**Zuordnung:** M5 (Beschleunigung). Grundlage: `docs/notes/dev-speedup-analysis.md` §5, §8.

## Inhalt
1. Gate-Semaphor rechnerweit (höchstens 2 volle Läufe gleichzeitig, weitere warten mit Meldung).
2. Inhaltsadressierter Gate-Cache je Paket und Rust (Hash über Quellen, Lockfiles, Toolchain): unveränderte Schritte werden übersprungen.
3. Rust: sccache, `cargo --offline` (gegen die Paket-Cache-Sperre), `.so`-Cache nach Quell-Hash für APK- und Integrationstest-Builds.

## Abnahmekriterien
- [ ] Zweites volles Gate ohne Änderung < 60 s; Worktree mit unverändertem `native/` ruft beim APK-Bau kein cargo auf.
- [ ] Selbsttests für Schlüsselbildung und Invalidierung; Gate grün.
