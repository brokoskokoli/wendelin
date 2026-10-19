#!/usr/bin/env bash
# Baut native/attest für Android (cargo-ndk) und legt die .so je ABI unter <ausgabe>/<abi>/ ab.
# Aufruf: tool/build_attest_android.sh <ausgabe> <abi>[,<abi>…]   (abi: arm64-v8a, armeabi-v7a, x86_64)
# Aus Gradle (app/android/app/build.gradle.kts, Task buildRustAttest); ANDROID_NDK_HOME setzt Gradle.
# WENDELIN_SKIP_RUST=1 überspringt den Bau (Dart-only-Arbeit; die App findet dann kein Prüfmodul).
# Cache (WP97): Die .so je ABI liegen unter ~/.cache/wendelin-gate/attest/<sha256(Quellen, Cargo.toml/.lock,
# rust-toolchain, NDK- und cargo-ndk-Version)>/<abi>/; bei Treffer wird cargo nicht aufgerufen.
# Aus bei CI=true oder WENDELIN_ATTEST_CACHE=0; Ordner überschreibbar mit WENDELIN_ATTEST_CACHE_DIR.
# sccache wird genutzt, wenn im PATH (nicht in CI).
set -euo pipefail
out="${1:?Ausgabeordner}"
abis="${2:?ABIs}"
root="$(cd "$(dirname "$0")/.." && pwd)"
if [ "${WENDELIN_SKIP_RUST:-}" = "1" ]; then
  echo "WARNUNG: Rust-Bau übersprungen (WENDELIN_SKIP_RUST=1), Attestierungsprüfung fehlt im APK." >&2
  exit 0
fi
# rustup ist unter Homebrew keg-only; Gradle erbt oft kein Shell-PATH.
# Vorn, damit ein Homebrew-cargo ohne Android-Targets nicht gewinnt.
# WENDELIN_RUST_BIN_DIRS (Doppelpunkt-Liste) ersetzt die Standardorte (für Tests).
IFS=':' read -ra rust_dirs <<<"${WENDELIN_RUST_BIN_DIRS-$HOME/.cargo/bin:/opt/homebrew/opt/rustup/bin:/usr/local/opt/rustup/bin}"
for d in ${rust_dirs[@]+"${rust_dirs[@]}"}; do
  [ -n "$d" ] && [ -d "$d" ] && PATH="$d:$PATH"
done
export PATH
for tool in cargo cargo-ndk; do
  command -v "$tool" >/dev/null || {
    echo "FEHLER: $tool fehlt. Setup: docs/ENGINEERING.md, Abschnitt Rust (rustup, Android-Targets, cargo install cargo-ndk)." >&2
    exit 1
  }
done
IFS=',' read -ra list <<<"$abis"
cd "$root/native/attest"

# sccache nur lokal und nur, wenn vorhanden und kein Wrapper gesetzt ist.
if [ "${CI:-}" != "true" ] && [ -z "${RUSTC_WRAPPER:-}" ] && command -v sccache >/dev/null; then
  export RUSTC_WRAPPER=sccache CARGO_INCREMENTAL=0
fi

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }

# Cache-Schlüssel; jeder Fehler (leerer Schlüssel) schaltet den Cache für diesen Lauf ab.
cache_root=""
key=""
if [ "${CI:-}" != "true" ] && [ "${WENDELIN_ATTEST_CACHE:-}" != "0" ]; then
  cache_root="${WENDELIN_ATTEST_CACHE_DIR:-$HOME/.cache/wendelin-gate/attest}"
  ndk_ver="$(cat "${ANDROID_NDK_HOME:-/nonexistent}/source.properties" 2>/dev/null)" || ndk_ver=""
  ndk_cli="$(cargo ndk --version 2>&1)" || ndk_cli=""
  rustc_ver="$(rustc -V 2>&1)" || rustc_ver=""
  key="$(
    [ -n "$ndk_ver" ] && [ -n "$ndk_cli" ] && [ -n "$rustc_ver" ] || exit 1
    {
      find . -type f ! -path './target/*' | LC_ALL=C sort | while IFS= read -r f; do
        printf '%s  ' "$f"
        sha256 <"$f" | cut -d' ' -f1
      done
      printf 'script  '
      sha256 <"${BASH_SOURCE[0]}" | cut -d' ' -f1
      printf 'ndk=%s\ncargo-ndk=%s\nrustc=%s RUSTFLAGS=%s\n' "$ndk_ver" "$ndk_cli" "$rustc_ver" "${RUSTFLAGS:-}"
    } | sha256 | cut -d' ' -f1
  )" || key=""
  [ ${#key} -eq 64 ] || { key=""; cache_root=""; }
fi
so=libwendelin_attest.so

missing=()
for a in "${list[@]}"; do
  if [ -n "$key" ] && [ -f "$cache_root/$key/$a/$so" ]; then
    mkdir -p "$out/$a" && cp "$cache_root/$key/$a/$so" "$out/$a/$so" || missing+=("$a")
  else
    missing+=("$a")
  fi
done
[ ${#missing[@]} -eq 0 ] && { echo "attest: .so aus dem Cache ($key)" >&2; exit 0; }

targets=()
for a in "${missing[@]}"; do targets+=(-t "$a"); done
cargo ndk "${targets[@]}" -o "$out" build --release --lib --locked
# cargo-ndk kopiert auch die cdylib der Abhängigkeit dcap-qvl mit; ins APK gehört nur unsere Bibliothek.
find "$out" -name '*.so' ! -name libwendelin_attest.so -delete

# Ergebnis ablegen (atomar: erst in ein tmp-Verzeichnis, dann umbenennen); Fehler sind nicht fatal.
if [ -n "$key" ]; then
  for a in "${missing[@]}"; do
    [ -f "$out/$a/$so" ] || continue
    (
      mkdir -p "$cache_root/$key" &&
        tmp="$(mktemp -d "$cache_root/.tmp.XXXXXX")" &&
        mkdir "$tmp/$a" && cp "$out/$a/$so" "$tmp/$a/$so" &&
        { mv "$tmp/$a" "$cache_root/$key/$a" 2>/dev/null || true; } &&
        rm -rf "$tmp"
    ) || true
  done
fi
