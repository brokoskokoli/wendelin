#!/usr/bin/env bash
# Baut native/attest für Android (cargo-ndk) und legt die .so je ABI unter <ausgabe>/<abi>/ ab.
# Aufruf: tool/build_attest_android.sh <ausgabe> <abi>[,<abi>…]   (abi: arm64-v8a, armeabi-v7a, x86_64)
# Aus Gradle (app/android/app/build.gradle.kts, Task buildRustAttest); ANDROID_NDK_HOME setzt Gradle.
# WENDELIN_SKIP_RUST=1 überspringt den Bau (Dart-only-Arbeit; die App findet dann kein Prüfmodul).
set -euo pipefail
out="${1:?Ausgabeordner}"
abis="${2:?ABIs}"
root="$(cd "$(dirname "$0")/.." && pwd)"
if [ "${WENDELIN_SKIP_RUST:-}" = "1" ]; then
  echo "WARNUNG: Rust-Bau übersprungen (WENDELIN_SKIP_RUST=1), Attestierungsprüfung fehlt im APK." >&2
  exit 0
fi
# rustup ist unter Homebrew keg-only; Gradle erbt oft kein Shell-PATH.
for d in "$HOME/.cargo/bin" /opt/homebrew/opt/rustup/bin /usr/local/opt/rustup/bin; do
  [ -d "$d" ] && PATH="$d:$PATH"
done
export PATH
for tool in cargo cargo-ndk; do
  command -v "$tool" >/dev/null || {
    echo "FEHLER: $tool fehlt. Setup: docs/ENGINEERING.md, Abschnitt Rust (rustup, Android-Targets, cargo install cargo-ndk)." >&2
    exit 1
  }
done
targets=()
IFS=',' read -ra list <<<"$abis"
for a in "${list[@]}"; do targets+=(-t "$a"); done
cd "$root/native/attest"
cargo ndk "${targets[@]}" -o "$out" build --release --lib --locked
# cargo-ndk kopiert auch die cdylib der Abhängigkeit dcap-qvl mit; ins APK gehört nur unsere Bibliothek.
find "$out" -name '*.so' ! -name libwendelin_attest.so -delete
