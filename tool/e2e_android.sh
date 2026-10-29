#!/usr/bin/env bash
# Gerätetests (WP11) auf einem Android-Emulator ohne Google Play (K7).
#
#   tool/e2e_android.sh [integration_test/<datei>.dart …]
#
# Emulator (WP124): Läuft keiner, startet das Skript das AVD Wendelin_AOSP_35
# selbst (tool/emulator_boot.sh: ohne Fenster/Audio, Port aus DEVICE=emulator-NNNN,
# sonst 5554, Log ${TMPDIR}/wendelin-emulator-<serial>.log, Boot-Zeitlimit
# EMU_BOOT_TIMEOUT, Standard 240 s) und beendet ihn am Ende jedes Laufs, auch bei
# Abbruch. E2E_KEEP_EMULATOR=1 lässt ihn laufen (mehrere Läufe hintereinander;
# der letzte ohne die Variable beendet ihn). Hängt zusätzlich ein echtes Gerät
# am USB, wird trotzdem der Emulator benutzt; echte Geräte werden nie gestartet
# oder beendet. Gleichzeitiger Start durch zwei Läufe: der zweite bricht ab.
#
# Das Skript
#   1. legt einen lokalen Kalender an, falls das Gerät keinen hat
#      (Content-Provider als Sync-Adapter, Kontotyp LOCAL),
#   2. erteilt die Kalender-Berechtigung, sobald `flutter test` die App
#      installiert hat (`pm grant` im Hintergrund – die Tests warten darauf),
#   3. tippt im Speichern-Dialog der Android-Dateiauswahl auf „Speichern“
#      (SAF-Test), da sich der System-Picker nicht aus Flutter bedienen lässt,
#   4. führt die Tests aus und prüft danach, dass kein Testtermin übrig ist.
#
# Umgebungsvariablen: ANDROID_SDK_ROOT (Standard ~/Library/Android/sdk),
# DEVICE bzw. ANDROID_SERIAL (ohne beides muss genau ein Gerät verbunden
# sein, sonst Abbruch). Läuft nur auf Emulatoren (Seriennummer emulator-*,
# ro.kernel.qemu=1); ein echtes Gerät nur mit E2E_ALLOW_DEVICE=1.
# Achtung, auf einem echten Gerät: Das Skript legt Testtermine im Kalender
# an, schreibt /sdcard/Download/wendelin-e2e-*.md und mit WENDELIN_MODELS
# /sdcard/Documents/WendelinE2E (wird danach gelöscht), setzt und entzieht
# die Assistenten-Rolle und löscht mit WENDELIN_LIVE oder WENDELIN_MODELS
# alle Wendelin-Daten (`pm clear app.wendelin`: Verläufe, Einstellungen,
# Keys, Modelle).
#
# Sprache und Assistent (M2, WP19): mit WENDELIN_MODELS=<dir> (darin
# whisper-base/, whisper-small/, silero-vad/ wie in tool/e2e_recognizer.sh)
# laufen auch voice_note_e2e_test.dart und overlay_e2e_test.dart. Das Skript
#   5. erteilt RECORD_AUDIO und kopiert per `run-as` die Modelle nach
#      files/models/ und die WAVs aus app/test/fixtures/stt/ nach
#      files/e2e/stt/ (einmal je Installation, Marke files/e2e/ready),
#   6. legt den Test-Vault /sdcard/Documents/WendelinE2E an und wählt ihn in
#      der Ordnerauswahl (Documents → WendelinE2E → „Use this folder“ →
#      „Allow“),
#   7. erledigt Aufträge der Tests aus files/e2e/host-request: `assist`
#      (Bildschirm an, Assistenten-Rolle per `cmd role add-role-holder`,
#      KEYCODE_ASSIST öffnet das Overlay), `back` (Overlay schließen, warten
#      bis die AssistantActivity weg ist), `meminfo` (`dumpsys meminfo` nach
#      files/e2e/meminfo.txt), `unrole` (Rolle entziehen, prüfen,
#      dass WendelinRecognitionService wieder aus ist),
#   8. räumt danach auf: Rolle entzogen, Test-Vault gelöscht, App-Daten
#      gelöscht (`pm clear`, auch die Modell-Kopien).
#
# Wake-Word-Dienst (WP50): integration_test/wake_service_e2e_test.dart nutzt die
# Aufträge `role` und `wake-loop` (WAKE_RUNS, WAKE_LOG=<datei> für das Log;
# WAKE_HIT=debug: der Test löst den Treffer per `debugHit` aus, WP149).
# WENDELIN_KEEP=1 lässt Rolle, App-Daten und den eingeschalteten Dienst stehen
# (Neustart-Test, WP54: `adb -s <emulator> reboot`, dann `wake-start source=vis`).
#
# Trainiertes Wake-Modell (WP129): WENDELIN_WAKE_DETECTOR=model (oder templates,
# auto) stellt „Erkennung“ im wake_service_e2e_test.dart ein; das Modell liegt
# in <WENDELIN_MODELS>/wake-classifier-wendelin/ (Datei wendelin_wp130_a.onnx).
#
# Sprach-Robustheit (WP30): WENDELIN_REPEAT=<n> wiederholt die Runden von
# voice_robustness_e2e_test.dart (je Runde D3 ohne und nach Overlay-Nutzung),
# E2E_VOICE_LOG=<datei> sammelt danach alle `Wendelin/voice`-Zeilen.
#
# Tests mit eigenem Skript (WP29): app_presence_e2e_test.dart
# (tool/e2e_app_presence.sh: Attrappen-APKs), mcp_e2e_test.dart und
# oauth_redirect_e2e_test.dart (tool/e2e_mcp.sh: Test-Server auf dem Rechner,
# `am start`-Rückleitungen) brauchen Vorbereitung, die dieses Skript nicht
# leistet. Im Sammellauf (ohne Argumente) werden sie nicht rot, sondern als
# „übersprungen – Skript X“ gemeldet; mit E2E_SCRIPTS=1 ruft das Skript
# sie danach selbst auf (dasselbe Gerät). Nennt man sie ausdrücklich als
# Argument, laufen sie ebenfalls über ihr Skript.
#
# Standort (WP104, integration_test/location_e2e_test.dart): nur wenn die Datei
# läuft, erteilt das Skript ACCESS_FINE/COARSE_LOCATION (`pm grant`), setzt per
# `adb emu geo fix` die Position (Hamburg, 10.0 / 53.55) und entzieht die
# Berechtigung danach wieder.
#
# Home Assistant (WP104, integration_test/ha_e2e_test.dart und ha_*_e2e_test.dart,
# z. B. WP154 ha_locked_e2e_test.dart): das Skript startet
# den Fake-HA app/tool/ha_test_server.dart (nur 127.0.0.1; Emulator: 10.0.2.2),
# übergibt HA_URL/HA_TOKEN und prüft danach das Server-Log (keine unerwarteten
# Aufrufe).
#
# Sprache der UI (WP104): E2E_LANG=de|en|fr|system (Standard de, unabhängig von
# der Emulator-Sprache) wird als --dart-define E2E_LANG an die Tests gegeben;
# die Tests lesen feste Texte aus l10n. Beide Sprachen: E2E_LANG=en wiederholen.
#
# Live (integration_test/live_e2e_test.dart, kostet ein paar Cent):
#   WENDELIN_LIVE=1 mit ANTHROPIC_API_KEY in der Umgebung. Der Key geht per
#   `adb shell run-as` über stdin in die privaten App-Daten (nicht auf die
#   Platte des Rechners, nicht in den Build), der Test löscht die Datei
#   sofort; nach dem Lauf werden die App-Daten gelöscht (`pm clear`).
set -euo pipefail

# Gradle braucht JDK 21 (neuere JDKs brechen den Build): nur wenn JAVA_HOME
# nicht gesetzt ist, openjdk@21 von Homebrew verwenden.
if [ -z "${JAVA_HOME:-}" ] && command -v brew >/dev/null 2>&1; then
  _jdk21="$(brew --prefix openjdk@21 2>/dev/null || true)/libexec/openjdk.jdk/Contents/Home"
  if [ -x "$_jdk21/bin/java" ]; then export JAVA_HOME="$_jdk21"; fi
fi
# Zweiter Ausweg: das JBR von Android Studio (JDK 27 scheitert an jlink).
_jbr="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
if [ -z "${JAVA_HOME:-}" ] && [ -x "$_jbr/bin/java" ]; then export JAVA_HOME="$_jbr"; fi

PKG=app.wendelin
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Emulator selbst starten, falls keiner läuft (WP124); DEVICE wird gesetzt.
# shellcheck source=tool/emulator_boot.sh
. "$ROOT/tool/emulator_boot.sh"
emu_boot_ensure || exit 1
# shellcheck source=tool/android_device.sh
. "$ROOT/tool/android_device.sh"

# Nur Emulatoren: Das Skript schreibt in den Kalender, tippt in der
# Dateiauswahl und löscht App-Daten. Ein echtes Gerät nur mit
# E2E_ALLOW_DEVICE=1.
if ! is_emulator; then
  if [ "${E2E_ALLOW_DEVICE:-}" != "1" ]; then
    echo "Abbruch: $DEVICE ist kein Emulator (Gerätetests schreiben in" \
      "Kalender und Dateien). Freigabe nur mit E2E_ALLOW_DEVICE=1." >&2
    exit 1
  fi
  echo "Warnung: E2E_ALLOW_DEVICE=1 – Tests laufen auf dem echten Gerät $DEVICE." \
    "Sie legen Testtermine an, schreiben /sdcard/Download/wendelin-e2e-*.md" \
    "und /sdcard/Documents/WendelinE2E (Test-Vault, wird gelöscht), ändern die" \
    "Assistenten-Rolle und löschen mit WENDELIN_LIVE/WENDELIN_MODELS alle" \
    "Wendelin-Daten (pm clear app.wendelin)." >&2
fi

# Ein Lauf je Emulator (WP110): belegt -> sofort Abbruch, Freigabe per trap (auch in cleanup).
# shellcheck source=tool/emulator_lock.sh
. "$ROOT/tool/emulator_lock.sh"
if ! emu_lock_acquire "$DEVICE"; then
  [ -z "$_EMU_STARTED_PID" ] || emu_boot_stop # selbst gestartet, aber nicht benutzbar
  exit 1
fi
# Bis cleanup steht: Emulator beenden VOR der Freigabe der Sperre.
trap 'emu_boot_stop; emu_lock_release' EXIT

if [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" != "1" ]; then
  echo "Gerät $DEVICE ist noch nicht hochgefahren" >&2
  exit 1
fi
if adb shell pm list packages | grep -q 'com.google.android.gms'; then
  echo "Warnung: Gerät hat Google Play Services (K7 verlangt AOSP ohne GMS)" >&2
fi

# 1. Lokaler Kalender
if ! adb shell content query --uri content://com.android.calendar/calendars \
  --projection _id | grep -q '_id='; then
  echo "Lege lokalen Kalender „Wendelin Test“ an"
  adb shell 'content insert --uri "content://com.android.calendar/calendars?caller_is_syncadapter=true&account_name=Wendelin%20Test&account_type=LOCAL" --bind account_name:s:"Wendelin Test" --bind account_type:s:LOCAL --bind name:s:wendelin_test --bind calendar_displayName:s:"Wendelin Test" --bind calendar_access_level:i:700 --bind ownerAccount:s:"Wendelin Test" --bind visible:i:1 --bind sync_events:i:1 --bind calendar_timezone:s:Europe/Berlin --bind calendar_color:i:-16776961'
fi

# 5. Sprache (optional): Modelle und WAVs prüfen
MODELS="${WENDELIN_MODELS:-}"
VAULT_DIR=/sdcard/Documents/WendelinE2E
if [ -n "$MODELS" ]; then
  for f in whisper-base/base-encoder.int8.onnx whisper-base/base-decoder.int8.onnx \
    whisper-base/base-tokens.txt whisper-small/small-encoder.int8.onnx \
    whisper-small/small-decoder.int8.onnx whisper-small/small-tokens.txt \
    silero-vad/silero_vad.onnx; do
    [ -f "$MODELS/$f" ] || { echo "Modell fehlt: $MODELS/$f" >&2; exit 1; }
  done
  adb shell mkdir -p "$VAULT_DIR"
fi

# 2. + 3. Helfer im Hintergrund
installed() { adb shell pm list packages "$PKG" | tr -d '\r' | grep -q "^package:$PKG\$"; }
in_app() { adb shell run-as "$PKG" "$@"; }
TMP=/data/local/tmp/wendelin-e2e
copy_in() { # <quelle auf dem Rechner> <ziel relativ zu files/>
  adb push "$1" "$TMP/x" >/dev/null 2>&1
  adb shell "cat $TMP/x | run-as $PKG sh -c 'cat > files/$2'"
  adb shell rm -f "$TMP/x"
}
# Trainiertes Wake-Modell (WP129, seit WP173 Voraussetzung zum Einschalten).
# Zweiteilig: fetch_classifier läuft VOR dem Hintergrund-Helfer im Hauptprozess
# (ein Fehler bricht den ganzen Lauf ab, set -e); push_classifier kopiert im
# Helfer aufs Gerät (scheitert es, wiederholt der Helfer es, bis es klappt).
# fetch: fehlt <MODELS>/wake-classifier-wendelin/<Datei> oder stimmt ihr SHA-256
# nicht mit dem Katalog, kommt sie aus der Release-URL (SHA-256 geprüft).
CLS_FILE=""
CLS_DIR=""
fetch_classifier() {
  [ -n "$MODELS" ] || return 0
  [ -d "$MODELS/wake-features" ] && [ -d "$MODELS/wake-e2e" ] || return 0
  local cat="$ROOT/packages/wendelin_voice/lib/src/models"
  local url sha
  CLS_FILE=$(sed -n "s/.*static const file = '\(.*\)';/\1/p" "$cat/wake_classifier_catalog.dart")
  url=$(grep -o "\$_wendelinRelease/[^']*" "$cat/wake_classifier_catalog.dart" | head -1)
  url="https://github.com/brokoskokoli/wendelin/releases/download${url#\$_wendelinRelease}"
  url="${url//\$file/$CLS_FILE}"
  sha=$(grep -A4 "name: file," "$cat/wake_classifier_catalog.dart" | sed -n "s/.*'\([0-9a-f]\{64\}\)'.*/\1/p")
  if [ -z "$CLS_FILE" ] || [ -z "$sha" ] || [ "${url#https://}" = "$url" ]; then
    echo "FEHLER: Katalogeintrag des Wake-Modells nicht lesbar ($cat/wake_classifier_catalog.dart)" >&2
    exit 1
  fi
  CLS_DIR="$MODELS/wake-classifier-wendelin"
  if [ -f "$CLS_DIR/$CLS_FILE" ] \
    && [ "$(shasum -a 256 "$CLS_DIR/$CLS_FILE" | cut -d' ' -f1)" != "$sha" ]; then
    echo "Wake-Modell lokal mit falschem SHA-256, lade neu …"
    rm -f "$CLS_DIR/$CLS_FILE"
  fi
  if [ ! -f "$CLS_DIR/$CLS_FILE" ]; then
    echo "Lade das Wake-Modell ($CLS_FILE) aus dem Release …"
    mkdir -p "$CLS_DIR"
    if ! curl -fsSL --retry 2 -o "$CLS_DIR/$CLS_FILE.part" "$url" \
      || [ "$(shasum -a 256 "$CLS_DIR/$CLS_FILE.part" | cut -d' ' -f1)" != "$sha" ]; then
      rm -f "$CLS_DIR/$CLS_FILE.part"
      echo "FEHLER: Wake-Modell nicht ladbar oder SHA-256 falsch ($url). Ohne dieses Modell lässt sich das Aktivierungswort nicht einschalten; Datei von Hand nach $CLS_DIR legen." >&2
      exit 1
    fi
    mv "$CLS_DIR/$CLS_FILE.part" "$CLS_DIR/$CLS_FILE"
  fi
}
# Läuft im Helfer, auch wenn files/e2e/ready schon steht (WENDELIN_KEEP). Eine
# Gerätedatei mit anderer Größe (veraltet) wird ersetzt.
push_classifier() {
  [ -n "$CLS_FILE" ] || return 0
  local want have
  want=$(wc -c <"$CLS_DIR/$CLS_FILE" | tr -d ' ')
  have=$(in_app sh -c "wc -c < files/models/wake-classifier-wendelin/$CLS_FILE" 2>/dev/null | tr -d ' \r') || have=""
  if [ "$have" != "$want" ]; then
    adb shell mkdir -p "$TMP"
    in_app mkdir -p files/models/wake-classifier-wendelin
    copy_in "$CLS_DIR/$CLS_FILE" "models/wake-classifier-wendelin/$CLS_FILE"
  fi
}
prepare_voice() {
  push_classifier
  in_app test -f files/e2e/ready 2>/dev/null && return 0
  echo "Kopiere Modelle und WAVs in die App-Daten …"
  adb shell mkdir -p "$TMP"
  in_app mkdir -p files/models/whisper-base files/models/whisper-small \
    files/models/silero-vad files/e2e/stt
  local id f
  for id in whisper-base whisper-small silero-vad; do
    for f in "$MODELS/$id"/*; do copy_in "$f" "models/$id/$(basename "$f")"; done
  done
  for f in "$ROOT"/app/test/fixtures/stt/*.wav; do
    copy_in "$f" "e2e/stt/$(basename "$f")"
  done
  if [ -d "$MODELS/wake-features" ] && [ -d "$MODELS/wake-e2e" ]; then
    # Aktivierungswort (WP60): openWakeWord-Modelle und WAVs zum Einlernen.
    in_app mkdir -p files/models/wake-features files/e2e/wake
    for f in "$MODELS"/wake-features/*; do
      copy_in "$f" "models/wake-features/$(basename "$f")"
    done
    for f in "$MODELS"/wake-e2e/*.wav; do
      copy_in "$f" "e2e/wake/$(basename "$f")"
    done
    # „Stopp“ (WP64b), falls vorhanden.
    for f in "$MODELS"/wake-e2e-stop/*.wav; do
      [ -f "$f" ] && copy_in "$f" "e2e/wake/$(basename "$f")"
    done
  fi
  in_app touch files/e2e/ready
  echo "Modelle und WAVs bereit"
}
# Text-Treffer im aktuellen uiautomator-Abzug antippen.
ui_dump() {
  adb shell uiautomator dump /sdcard/wendelin_ui.xml >/dev/null 2>&1 || true
  adb shell cat /sdcard/wendelin_ui.xml 2>/dev/null | tr '>' '\n'
}
tap_text() { # <abzug> <text-regex>
  local bounds n
  bounds="$(echo "$1" | grep -E "text=\"($2)\"" |
    grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | head -1 || true)"
  [ -n "$bounds" ] || return 1
  read -r -a n <<<"$(echo "$bounds" | tr -c '0-9' ' ')"
  adb shell input tap $(((n[0] + n[2]) / 2)) $(((n[1] + n[3]) / 2))
}
resumed() { adb shell dumpsys activity activities 2>/dev/null | grep -E 'topResumedActivity|mResumedActivity'; }
LOCK_PIN=4711
# WP99: Stationsmodus. Die Station ist sichtbar, wenn StationActivity oben liegt.
# Hinweis: kein `cmd | grep -q` unter pipefail (grep -q beendet früh, der Schreiber
# bekommt SIGPIPE, die Pipeline gilt als Fehlschlag). Erst in Variable lesen.
station_visible() { local out; out="$(resumed || true)"; grep -q StationActivity <<<"$out"; }
station_wait() { # sichtbar (0) oder nicht (1) innerhalb von 20 s
  local want="$1" _
  for _ in $(seq 1 40); do
    if station_visible; then [ "$want" = up ] && return 0; else [ "$want" = gone ] && return 0; fi
    sleep 0.5
  done
  return 1
}
station_note() { in_app sh -c "'echo \"$1\" >> files/e2e/station-result.txt'"; }
station_pin_shown() {
  local out
  out="$(ui_dump || true)"
  grep -qE 'pinEntry|keyguard_pin_view|passwordEntry|keyguard_bouncer' <<<"$out"
}
station_tap_end() { # „Beenden“ (de) bzw. End/Terminer antippen
  local ui
  ui="$(ui_dump)"
  grep -qE '(text|content-desc)="(Beenden|End|Terminer)"' <<<"$ui" || return 1
  local bounds n
  bounds="$(echo "$ui" | grep -E '(text|content-desc)="(Beenden|End|Terminer)"' |
    grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | head -1)"
  read -r -a n <<<"$(echo "$bounds" | tr -c '0-9' ' ')"
  adb shell input tap $(((n[0] + n[2]) / 2)) $(((n[1] + n[3]) / 2))
}
wake_loop() { # <Durchläufe>
  local n="$1" i ok=0 answered=0 found log gapmax=-9999 silmax=0 gaps=0 g line m sl zmax=0 z conflicts=0 keeps=0 mute=0 ml
  log="${WAKE_LOG:-/dev/null}"
  for i in $(seq 1 "$n"); do
    adb shell input keyevent KEYCODE_SLEEP
    sleep 2
    # WP149 (WAKE_HIT=debug): statt der eingespeisten WAV löst der Test den Treffer des
    # Dienstes selbst aus (`debugHit`); er sieht diese Datei und löscht sie.
    [ "${WAKE_HIT:-}" = debug ] && in_app sh -c "'touch files/e2e/hit-request'"
    found=0
    for _ in $(seq 1 120); do
      resumed | grep -q AssistantActivity && { found=1; break; }
      sleep 0.5
    done
    if [ "$found" = 1 ]; then
      # Der Satz im Overlay: erkannt, wenn die Antwort des Skripts („Alles klar.“)
      # im Abzug steht (uiautomator liest content-desc).
      for _ in $(seq 1 $([ "${WAKE_HIT:-}" = debug ] && echo 6 || echo 60)); do
        ui_dump | grep -q 'Alles klar' && { answered=$((answered + 1)); break; }
        sleep 1
      done
      echo "UI: $(ui_dump | grep -oE '(text|content-desc)="[^"]+"' | tr '\n' '|')" >>"$log"
      adb logcat -d | grep 'Wendelin/voice' >>"$log" || true
      if adb logcat -d | grep -q 'mic-ready.*trigger=wakeWord'; then ok=$((ok + 1)); fi
      # WP149: größte Lücke (`ms`) und Stille (`silence`) der Übergabe (nur Zahlen).
      g="$(adb logcat -d | grep -E 'Wendelin/voice: wake-gap ' | tr -d '\r' || true)"
      z=""
      while read -r line; do
        [ -n "$line" ] || continue
        gaps=$((gaps + 1))
        m="$(grep -oE ' ms=-?[0-9]+' <<<"$line" | head -1 | tr -dc '0-9-' || true)"
        sl="$(grep -oE ' silence=[0-9]+' <<<"$line" | head -1 | tr -dc '0-9' || true)"
        [ -n "$m" ] && [ "$m" -gt "$gapmax" ] && gapmax="$m"
        [ -n "$sl" ] && [ "$sl" -gt "$silmax" ] && silmax="$sl"
        z="$(grep -oE ' tailZero=[0-9]+' <<<"$line" | head -1 | tr -dc '0-9' || true)"
        [ -n "$z" ] && [ "$z" -gt "$zmax" ] && zmax="$z"
      done <<<"$g"
      # Konsistenz statt Maximum (der Emulator-Ton ist unzuverlässig, beide Mikrofone können
      # nur Nullen liefern): ein Rest mit 100 % Nullen ist nur dann „stumm“, wenn das App-Mikrofon
      # im selben Durchlauf Signal hatte (kleinster `zero` der `mic-level` < 100).
      ml="$(adb logcat -d | grep -E 'Wendelin/voice: mic-level ' | grep -oE ' zero=[0-9]+' | tr -dc '0-9\n' | sort -n | head -1 || true)"
      [ "$z" = 100 ] && [ -n "$ml" ] && [ "$ml" -lt 100 ] && mute=$((mute + 1))
      # Beleg der Ursache (nur Zahlen): Konflikt in der Überlappung gesehen und behalten.
      conflicts=$((conflicts + $(adb logcat -d | grep -c 'wake-conflict reason=recording handoff=kept' || true)))
      keeps=$((keeps + $(adb logcat -d | grep -c 'wake-conflict reason=recording handoff=kept action=keep' || true)))
      adb logcat -c
      adb shell input keyevent KEYCODE_BACK
      for _ in $(seq 1 40); do
        adb shell dumpsys activity activities | grep -q 'app.wendelin/.AssistantActivity' || break
        sleep 0.5
      done
      sleep 3
    fi
    if [ "$found" = 0 ]; then
      adb logcat -d | grep -E 'Wendelin/voice|wake' >>"$log" || true
      adb logcat -c
    fi
    echo "Durchlauf $i: overlay=$found scenario=$(in_app cat files/e2e/scenario 2>/dev/null)" >>"$log"
  done
  adb shell input keyevent KEYCODE_WAKEUP
  echo "wakeWord=$ok/$n answered=$answered/$n gaps=$gaps gapMaxMs=$gapmax silenceMaxMs=$silmax tailZeroMaxPct=$zmax tailMute=$mute conflicts=$conflicts keeps=$keeps" |
    adb shell run-as "$PKG" sh -c "'cat > files/e2e/wake-result.txt'"
}
host_request() {
  local action
  action="$(in_app cat files/e2e/host-request 2>/dev/null | tr -d '\r' || true)"
  [ -n "$action" ] || return 0
  in_app rm -f files/e2e/host-request
  case "$action" in
    assist)
      adb shell input keyevent KEYCODE_WAKEUP
      adb shell wm dismiss-keyguard >/dev/null 2>&1 || true
      if ! adb shell cmd role get-role-holders android.app.role.ASSISTANT | grep -q "$PKG"; then
        adb shell cmd role add-role-holder --user 0 android.app.role.ASSISTANT "$PKG"
        sleep 2
      fi
      adb shell input keyevent KEYCODE_ASSIST
      for _ in $(seq 1 40); do resumed | grep -q AssistantActivity && break; sleep 0.5; done
      ;;
    assist-locked)
      # WP53: gesperrtes Gerät (PIN nur auf dem Emulator), Bildschirm aus und
      # an (Sperrbildschirm), dann KEYCODE_ASSIST. Entfernt wird die PIN von
      # `unlock` und beim Aufräumen.
      is_emulator || { echo "Sperre nur auf dem Emulator" >&2; exit 1; }
      # Ist die PIN schon gesetzt (zweite Runde), schlägt set-pin fehl; dann prüfen.
      adb shell locksettings set-pin "$LOCK_PIN" >/dev/null 2>&1 ||
        adb shell locksettings verify --old "$LOCK_PIN" >/dev/null 2>&1 ||
        { echo "PIN konnte nicht gesetzt werden" >&2; exit 1; }
      adb shell input keyevent KEYCODE_SLEEP
      sleep 2
      adb shell input keyevent KEYCODE_WAKEUP
      sleep 2
      if ! adb shell cmd role get-role-holders android.app.role.ASSISTANT | grep -q "$PKG"; then
        adb shell cmd role add-role-holder --user 0 android.app.role.ASSISTANT "$PKG"
        sleep 2
      fi
      adb shell input keyevent KEYCODE_ASSIST
      for _ in $(seq 1 40); do resumed | grep -q AssistantActivity && break; sleep 0.5; done
      ;;
    unlock)
      # Nur bei gesperrtem Gerät aufrufen (locked_flashlight_e2e_test): erst die
      # PIN wirklich im Bouncer eintippen, damit der Entsperr-Callback der App
      # (requestDismissKeyguard) eintrifft; danach die PIN entfernen (WP114).
      adb shell input keyevent KEYCODE_WAKEUP
      adb shell input swipe 540 1800 540 600 >/dev/null 2>&1 || true
      sleep 1
      adb shell input text "$LOCK_PIN" >/dev/null 2>&1 || true
      adb shell input keyevent KEYCODE_ENTER >/dev/null 2>&1 || true
      sleep 3
      adb shell locksettings clear --old "$LOCK_PIN" >/dev/null 2>&1 || true
      adb shell input keyevent KEYCODE_WAKEUP
      adb shell wm dismiss-keyguard >/dev/null 2>&1 || true
      ;;
    back)
      adb shell input keyevent KEYCODE_BACK
      for _ in $(seq 1 40); do
        adb shell dumpsys activity activities | grep -q 'app.wendelin/.AssistantActivity' || break
        sleep 0.5
      done
      ;;
    role)
      # Nur die Assistenten-Rolle (WP50: der Wake-Word-Dienst braucht sie). Neu
      # vergeben, damit das System den VoiceInteractionService der frisch
      # installierten App bindet.
      adb shell cmd role remove-role-holder --user 0 android.app.role.ASSISTANT "$PKG" || true
      sleep 1
      adb shell cmd role add-role-holder --user 0 android.app.role.ASSISTANT "$PKG"
      sleep 3
      ;;
    wake-loop)
      # WP50: je Durchlauf Bildschirm aus, warten bis die eingespeiste WAV das
      # Overlay öffnet, prüfen (trigger=wakeWord, Antwort im Overlay), mit
      # BACK schließen. Ergebnis nach files/e2e/wake-result.txt, das ganze
      # Log (nur Wendelin-Zeilen, ohne Inhalte) nach $WAKE_LOG, falls gesetzt.
      wake_loop "${WAKE_RUNS:-10}"
      ;;
    station-tile)
      # WP99: Schnellkachel antippen (`cmd statusbar click-tile`, Android 13+).
      # click-tile wirkt nur, wenn die Kachel im QS-Panel liegt: vorher add-tile.
      adb shell cmd statusbar add-tile app.wendelin/app.wendelin.StationTileService >/dev/null 2>&1 || true
      sleep 2
      adb shell cmd statusbar click-tile app.wendelin/app.wendelin.StationTileService >/dev/null 2>&1 || true
      adb shell cmd statusbar remove-tile app.wendelin/app.wendelin.StationTileService >/dev/null 2>&1 || true
      station_wait up && station_note tile_started=1 || station_note tile_started=0
      ;;
    station-check)
      # WP99: Zustand notieren (sichtbar, PIN-Abfrage offen).
      station_visible && station_note "visible=1" || station_note "visible=0"
      station_pin_shown && station_note "pin=1" || station_note "pin=0"
      ;;
    station-lock)
      # PIN setzen, Bildschirm aus und an: die Station liegt über der Sperre.
      is_emulator || { echo "Sperre nur auf dem Emulator" >&2; exit 1; }
      adb shell locksettings set-pin "$LOCK_PIN" >/dev/null 2>&1 ||
        adb shell locksettings verify --old "$LOCK_PIN" >/dev/null 2>&1 ||
        { echo "PIN konnte nicht gesetzt werden" >&2; exit 1; }
      adb shell input keyevent KEYCODE_SLEEP
      sleep 2
      adb shell input keyevent KEYCODE_WAKEUP
      sleep 2
      local win
      win="$(adb shell dumpsys window | tr -d '\r' || true)"
      if grep -qiE 'isKeyguardShowing=true|mShowingLockscreen=true|keyguardShowing=true' <<<"$win"; then
        station_note locked=1
      else
        station_note locked=0
      fi
      station_visible && station_note shown_locked=1 || station_note shown_locked=0
      ;;
    station-end-cancel)
      # „Beenden“ tippen: die PIN-Abfrage kommt; abbrechen (BACK): die Station bleibt.
      station_tap_end && station_note end_tapped=1 || station_note end_tapped=0
      sleep 2
      station_pin_shown && station_note pin_asked=1 || station_note pin_asked=0
      adb shell input keyevent KEYCODE_BACK
      sleep 2
      station_visible && station_note stays_after_cancel=1 || station_note stays_after_cancel=0
      ;;
    station-end-pin)
      # „Beenden“ und die richtige PIN: die Station geht zu.
      station_tap_end || true
      sleep 2
      adb shell input text "$LOCK_PIN"
      adb shell input keyevent KEYCODE_ENTER
      station_wait gone && station_note ended_after_pin=1 || station_note ended_after_pin=0
      ;;
    station-unlock)
      adb shell locksettings clear --old "$LOCK_PIN" >/dev/null 2>&1 || true
      adb shell input keyevent KEYCODE_WAKEUP
      adb shell wm dismiss-keyguard >/dev/null 2>&1 || true
      ;;
    meminfo)
      # Speicher der App (B14, WP30): TOTAL PSS/RSS und Native Heap.
      adb shell dumpsys meminfo "$PKG" | tr -d '\r' |
        grep -E 'TOTAL PSS|TOTAL RSS|TOTAL SWAP|Native Heap:|^ *TOTAL ' |
        adb shell run-as "$PKG" sh -c "'cat > files/e2e/meminfo.txt'"
      ;;
    unrole)
      # `am instrument` (Start jedes instrumentierten Tests) beendet die App per
      # force-stop; das System bindet den VoiceInteractionService danach nicht
      # neu, solange die Rolle gehalten bleibt (z. B. von einem Test davor).
      # Ohne gebundenen Dienst gibt es beim Entzug kein onShutdown. Darum die
      # Rolle zuerst neu vergeben, damit der Dienst im laufenden Prozess hängt.
      adb shell cmd role remove-role-holder --user 0 android.app.role.ASSISTANT "$PKG" || true
      sleep 1
      adb shell cmd role add-role-holder --user 0 android.app.role.ASSISTANT "$PKG"
      sleep 3
      adb shell cmd role remove-role-holder --user 0 android.app.role.ASSISTANT "$PKG"
      sleep 3
      # Nur der Abschnitt enabledComponents (bis zur nächsten Überschrift).
      if adb shell dumpsys package "$PKG" | tr -d '\r' |
        awk '/enabledComponents:/ {on = 1; next} on && /^ *[A-Za-z]+:$/ {on = 0} on' |
        grep -q WendelinRecognitionService; then
        in_app sh -c "'echo aktiv > files/e2e/recognizer-state'"
      else
        in_app sh -c "'echo aus > files/e2e/recognizer-state'"
      fi
      ;;
  esac
  in_app touch "files/e2e/host-done-$action"
}
LIVE="${WENDELIN_LIVE:-}"
if [ -n "$LIVE" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "WENDELIN_LIVE gesetzt, aber ANTHROPIC_API_KEY fehlt" >&2
  exit 1
fi
# WP104: Standort-Test? (Sammellauf ohne Argumente schließt ihn ein.)
NEED_LOC=0
# WP99: Der Stationstest braucht die Host-Aufträge (Kachel, Sperre, PIN) auch ohne Modelle.
NEED_STATION=0
if [ $# -eq 0 ]; then
  NEED_LOC=1
  NEED_STATION=1
else
  for a in "$@"; do
    case "$a" in
      *location_e2e_test.dart) NEED_LOC=1 ;;
      *station_e2e_test.dart) NEED_STATION=1 ;;
    esac
  done
fi
LOC_LON=10.0
LOC_LAT=53.55
helper() {
  local granted="" pushed="" voiced="" located=""
  while true; do
    if [ -z "$granted" ] && installed; then
      if adb shell pm grant "$PKG" android.permission.READ_CALENDAR 2>/dev/null &&
        adb shell pm grant "$PKG" android.permission.WRITE_CALENDAR 2>/dev/null &&
        # SEND_SMS vorab (vor jedem add-role-holder): Als Rollenbestandteil
        # erteilt, nimmt der Rollenentzug es zurück und Android beendet den
        # instrumentierten Prozess („permissions revoked“).
        adb shell pm grant "$PKG" android.permission.SEND_SMS 2>/dev/null; then
        granted=1
      fi
    fi
    if [ -n "$LIVE" ] && [ -n "$granted" ] && [ -z "$pushed" ]; then
      if printf '%s' "$ANTHROPIC_API_KEY" | adb shell run-as "$PKG" \
        sh -c "'mkdir -p files && cat > files/live_anthropic.key'" 2>/dev/null; then
        pushed=1
      fi
    fi
    if [ "$NEED_LOC" = 1 ] && [ -z "$located" ] && installed; then
      if adb shell pm grant "$PKG" android.permission.ACCESS_FINE_LOCATION 2>/dev/null &&
        adb shell pm grant "$PKG" android.permission.ACCESS_COARSE_LOCATION 2>/dev/null &&
        adb emu geo fix "$LOC_LON" "$LOC_LAT" >/dev/null 2>&1; then
        located=1
      fi
    fi
    if [ -n "$granted" ] && ! installed; then
      granted="" # neu installiert: erneut erteilen
      voiced=""
      located=""
    fi
    if [ -n "$MODELS" ] && [ -n "$granted" ] && [ -z "$voiced" ]; then
      adb shell pm grant "$PKG" android.permission.RECORD_AUDIO 2>/dev/null &&
        prepare_voice && voiced=1
    fi
    # Dateiauswahl im Vordergrund: „Speichern“ (Liste) bzw. den Test-Vault
    # (Ordnerauswahl) antippen.
    if resumed | grep -q documentsui; then
      local ui
      ui="$(ui_dump)"
      tap_text "$ui" 'ALLOW|Zulassen|ZULASSEN|SAVE|Speichern|SPEICHERN' ||
        { echo "$ui" | grep -q 'text="Files in WendelinE2E"' &&
          tap_text "$ui" 'USE THIS FOLDER|DIESEN ORDNER VERWENDEN'; } ||
        tap_text "$ui" 'WendelinE2E' || tap_text "$ui" 'Documents' || true
    fi
    if [ -n "$voiced" ] || { [ "$NEED_STATION" = 1 ] && [ -n "$granted" ]; }; then host_request; fi
    sleep 1
  done
}
fetch_classifier # im Hauptprozess: ein Fehler beendet den Lauf (set -e)
helper &
HELPER=$!
HA_SERVER=
cleanup() {
  kill "$HELPER" 2>/dev/null || true
  # Fake-HA (run_ha) nach Abbruch nicht verwaist lassen.
  if [ -n "$HA_SERVER" ]; then
    # shellcheck disable=SC2046
    kill $(pgrep -P "$HA_SERVER" 2>/dev/null) "$HA_SERVER" 2>/dev/null || true
  fi
  # Sperre aus WP53 sicher entfernen (nur Emulator).
  if is_emulator; then
    adb shell locksettings clear --old "$LOCK_PIN" >/dev/null 2>&1 || true
  fi
  if [ -n "$LIVE" ]; then
    adb shell run-as "$PKG" rm -f files/live_anthropic.key 2>/dev/null || true
  fi
  if installed; then adb shell pm revoke "$PKG" android.permission.SEND_SMS 2>/dev/null || true; fi
  if [ "$NEED_LOC" = 1 ] && installed; then
    adb shell pm revoke "$PKG" android.permission.ACCESS_FINE_LOCATION 2>/dev/null || true
    adb shell pm revoke "$PKG" android.permission.ACCESS_COARSE_LOCATION 2>/dev/null || true
  fi
  # Testdateien der Dateiauswahl und den uiautomator-Abzug entfernen.
  adb shell 'rm -f /sdcard/Download/wendelin-e2e-*.md /sdcard/wendelin_ui.xml' 2>/dev/null || true
  if [ -n "$MODELS" ] && [ -z "${WENDELIN_KEEP:-}" ]; then
    adb shell cmd role remove-role-holder --user 0 android.app.role.ASSISTANT "$PKG" 2>/dev/null || true
    adb shell rm -rf "$VAULT_DIR" "$TMP" 2>/dev/null || true
    if installed; then adb shell pm clear "$PKG" >/dev/null || true; fi
  fi
  # Emulator beenden (WP124), erst danach die Sperre freigeben.
  emu_boot_stop
  emu_lock_release
}
trap cleanup EXIT

# 4. Tests
cd "$ROOT/app"
COLLECT=0
if [ $# -eq 0 ]; then
  COLLECT=1
  set -- integration_test/*_test.dart
fi
# Tests mit eigenem Skript herausnehmen (siehe Kopf).
script_for() { # <test.dart> -> Skript oder leer
  case "$(basename "$1")" in
    app_presence_e2e_test.dart) echo tool/e2e_app_presence.sh ;;
    mcp_e2e_test.dart | oauth_redirect_e2e_test.dart) echo tool/e2e_mcp.sh ;;
  esac
}
SCRIPTS=()
KEEP=()
for f in "$@"; do
  s="$(script_for "$f")"
  if [ -z "$s" ]; then
    KEEP+=("$f")
  else
    case " ${SCRIPTS[*]-} " in *" $s "*) ;; *) SCRIPTS+=("$s") ;; esac
  fi
done
set -- ${KEEP[@]+"${KEEP[@]}"}
status=0
DEFINES=()
if [ -n "$LIVE" ]; then DEFINES+=(--dart-define=WENDELIN_LIVE=true); fi
if [ -n "$MODELS" ]; then DEFINES+=(--dart-define=WENDELIN_VOICE_E2E=true); fi
# WP103: Ordner (unter files/e2e/) mit den vorab kopierten Modellen.
if [ -n "${WENDELIN_WP103_MODELS:-}" ]; then
  DEFINES+=(--dart-define=WENDELIN_WP103_MODELS="$WENDELIN_WP103_MODELS")
fi
# WP104: Sprache der UI in den Tests (Standard de, nicht die Emulator-Sprache).
DEFINES+=(--dart-define=E2E_LANG="${E2E_LANG:-de}")
# WP92a: Ordner (unter files/e2e/) mit CAM++-Modell und synthetischen WAVs.
if [ -n "${WENDELIN_WP92A_DIR:-}" ]; then
  DEFINES+=(--dart-define=WENDELIN_WP92A_DIR="$WENDELIN_WP92A_DIR")
fi
# WP54: der Wake-Word-Dienst bleibt nach dem Test an (Neustart-Prüfung).
if [ -n "${WENDELIN_WAKE_DETECTOR:-}" ]; then
  DEFINES+=(--dart-define=WENDELIN_WAKE_DETECTOR="$WENDELIN_WAKE_DETECTOR")
fi
if [ -n "${WENDELIN_KEEP:-}" ]; then DEFINES+=(--dart-define=WENDELIN_KEEP=true); fi
# Wiederholungen der Sprach-Robustheit (WP30, voice_robustness_e2e_test.dart).
if [ -n "${WENDELIN_REPEAT:-}" ]; then
  DEFINES+=(--dart-define=WENDELIN_REPEAT="$WENDELIN_REPEAT")
fi

# Tests, die eine zweite Engine der App starten (Overlay), definieren deren
# Dart-Einstieg selbst (`@pragma('vm:entry-point')`): Die Engine sucht ihn in
# der Root-Bibliothek, und die ist nur bei `flutter build -t <test>` die
# Testdatei (bei `flutter test` ein generierter Listener). Sie laufen deshalb
# über Android-Instrumentierung (androidTest/…/FlutterE2eTest.kt).
PLAIN=()
INSTRUMENTED=()
HA=()
for f in "$@"; do
  if [ -f "$f" ] && grep -q "pragma('vm:entry-point')" "$f"; then
    INSTRUMENTED+=("$f")
  elif case "$(basename "$f")" in ha_e2e_test.dart | ha_*_e2e_test.dart) true ;; *) false ;; esac; then
    HA+=("$f") # braucht den Fake-HA (WP104), eigener Lauf
  else
    PLAIN+=("$f")
  fi
done
run_instrumented() { # <test.dart>
  echo "Instrumentiert: $1"
  # Zuerst die App bauen: Das legt in frischen Worktrees erst android/gradlew an.
  flutter build apk --debug -t "$1" ${DEFINES[@]+"${DEFINES[@]}"} >/dev/null
  (cd android && ./gradlew -q app:assembleDebugAndroidTest >/dev/null)
  adb install -r build/app/outputs/flutter-apk/app-debug.apk >/dev/null
  adb install -r build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk >/dev/null
  adb logcat -c
  adb logcat -G 16M >/dev/null 2>&1 || true
  local out
  out="$(adb shell am instrument -w -r -e class "$PKG.FlutterE2eTest" \
    "$PKG.test/androidx.test.runner.AndroidJUnitRunner" | tr -d '\r')"
  # Ausgaben der Dart-Tests (Messwerte, Fehler) aus logcat.
  adb logcat -d -s flutter | grep -E 'M2-|WP30-|TOTAL|Native Heap|EXCEPTION|Expected|Actual|Notiz|fail' | cut -c 33- || true
  # Diagnosezeilen ohne Inhalte (WP30) aller Engines und der Session.
  if [ -n "${E2E_VOICE_LOG:-}" ]; then
    adb logcat -d | grep 'Wendelin/voice' >"$E2E_VOICE_LOG" || true
  fi
  echo "$out" | grep -E 'INSTRUMENTATION_STATUS: (test|stack)=|^OK|FAILURES|Tests run|INSTRUMENTATION_FAILED' | head -20 || true
  adb uninstall "$PKG.test" >/dev/null 2>&1 || true
  if ! echo "$out" | grep -q '^OK ('; then
    echo "Instrumentierung nicht OK; Ende der Rohausgabe:" >&2
    echo "$out" | tail -8 | cut -c 1-300 >&2
    return 1
  fi
}
# WP91/WP104: Fake-Home-Assistant auf dem Rechner (nur 127.0.0.1, der Emulator
# erreicht ihn als 10.0.2.2), dann der Test mit HA_URL/HA_TOKEN; danach darf
# das Server-Log keine `unexpected`-Zeile (401/404, unbekannter Aufruf) enthalten.
run_ha() { # <test.dart>
  local token work server port st=0
  token="e2e-$(date +%s)"
  work="$(mktemp -d)"
  mkfifo "$work/in"
  (dart run tool/ha_test_server.dart --token "$token" <"$work/in" >"$work/out" 2>"$work/err") &
  server=$!
  HA_SERVER=$server
  exec 3>"$work/in"
  for _ in $(seq 1 120); do grep -q 'port=[0-9]' "$work/out" 2>/dev/null && break; sleep 0.5; done
  port="$(grep -oE '(^|[^_])port=[0-9]+' "$work/out" | head -1 | cut -d= -f2)"
  if [ -z "$port" ]; then
    echo "Fake-HA startet nicht: $(cat "$work/err")" >&2
    st=1
  else
    echo "Fake-HA auf 127.0.0.1:$port (Emulator: 10.0.2.2:$port)"
    flutter test "$1" ${DEFINES[@]+"${DEFINES[@]}"} -d "$DEVICE" \
      --dart-define=HA_URL="http://10.0.2.2:$port" \
      --dart-define=HA_TOKEN="$token" 3>&- || st=$?
  fi
  exec 3>&- || true
  for _ in $(seq 1 10); do kill -0 "$server" 2>/dev/null || break; sleep 0.5; done
  # shellcheck disable=SC2046
  kill $(pgrep -P "$server" 2>/dev/null) 2>/dev/null || true
  # Endet der Server nicht von selbst (stdin-EOF der FIFO kam nicht an), wäre
  # `wait` endlos blockiert (WP104: Lauf hing nach dem grünen HA-Test).
  kill "$server" 2>/dev/null || true
  wait "$server" 2>/dev/null || true
  HA_SERVER=
  echo "--- Fake-HA-Anfragen (Zusammenfassung)"
  sort "$work/err" | uniq -c
  if grep -q 'unexpected' "$work/err"; then
    echo "Fake-HA sah unerwartete Aufrufe" >&2
    st=1
  fi
  rm -rf "$work"
  return $st
}
if [ ${#PLAIN[@]} -gt 0 ]; then
  flutter test "${PLAIN[@]}" ${DEFINES[@]+"${DEFINES[@]}"} -d "$DEVICE" || status=$?
fi
for f in ${HA[@]+"${HA[@]}"}; do
  run_ha "$f" || status=1
done
for f in ${INSTRUMENTED[@]+"${INSTRUMENTED[@]}"}; do
  run_instrumented "$f" || status=1
done
if [ -n "$LIVE" ] && installed; then
  adb shell pm clear "$PKG" >/dev/null || true
fi

if [ ${#SCRIPTS[@]} -gt 0 ]; then
  # Der Hintergrund-Helfer (Berechtigungen, Modelle, Dateiauswahl) würde die
  # Skripte stören (run-as auf eine gerade deinstallierte App).
  kill "$HELPER" 2>/dev/null || true
  if [ "$COLLECT" = 1 ] && [ "${E2E_SCRIPTS:-}" != "1" ]; then
    for s in "${SCRIPTS[@]}"; do
      echo "übersprungen – Skript $s (eigene Vorbereitung; E2E_SCRIPTS=1 ruft es auf)"
    done
  else
    for s in "${SCRIPTS[@]}"; do
      echo "Skript $s"
      DEVICE="$DEVICE" bash "$ROOT/$s" || status=1
    done
  fi
fi

left="$(adb shell "content query --uri content://com.android.calendar/events --projection _id --where \"title='Tauchen' AND deleted=0\"" | grep -c '_id=' || true)"
if [ "$left" != "0" ]; then
  echo "Fehler: $left Testtermin(e) „Tauchen“ im Gerätekalender übrig" >&2
  status=1
fi
exit $status
