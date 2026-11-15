#!/usr/bin/env bash
# Emulator smoke test: install, launch, visit screens, start playback, capture screenshots.
# Fails if the app process dies or logcat shows a fatal exception from the app.
set -uo pipefail
APK="$1"
OUT="${2:-smoke}"
PKG=io.github.worldtv.android
mkdir -p "$OUT"

shot() { adb exec-out screencap -p > "$OUT/$1.png"; echo "screenshot $1"; }
dump() { adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb shell cat /sdcard/ui.xml > "$OUT/ui.xml" 2>/dev/null; }
# Tap the centre of the first node whose text or content-desc matches $1 (regex).
tap_text() {
  dump
  local b
  b=$(python3 - "$1" "$OUT/ui.xml" <<'PY'
import re, sys
pat, path = sys.argv[1], sys.argv[2]
xml = open(path, encoding="utf-8", errors="ignore").read()
for m in re.finditer(r'<node [^>]*>', xml):
    n = m.group(0)
    t = re.search(r'text="([^"]*)"', n); d = re.search(r'content-desc="([^"]*)"', n)
    vals = [(t.group(1) if t else ""), (d.group(1) if d else "")]
    if any(v and re.search(pat, v) for v in vals):
        x1, y1, x2, y2 = map(int, re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n).groups())
        print((x1 + x2) // 2, (y1 + y2) // 2); break
PY
)
  if [[ -n "$b" ]]; then adb shell input tap $b; echo "tapped '$1' at $b"; return 0; fi
  echo "could not find '$1'"; return 1
}
alive() { adb shell pidof "$PKG" >/dev/null; }

adb logcat -c
adb install -r "$APK"
adb shell am start -W -n "$PKG/io.github.worldtv.MainActivity"
sleep 8;  shot 01-launch
# The first launch downloads the iptv-org directory.
for i in $(seq 1 18); do
  dump; grep -q "Popular now" "$OUT/ui.xml" && break; sleep 5
done
shot 02-home
tap_text '^Explore$' && sleep 3 && shot 03-explore
tap_text '^Search$' && sleep 2 && adb shell input text "news" && sleep 3 && shot 04-search
tap_text '^Guide$' && sleep 2 && shot 05-guide
tap_text '^Library$' && sleep 2 && shot 06-library
tap_text '^Home$' && sleep 3
tap_text '^LIVE$' || tap_text 'channels'
sleep 25; shot 07-player
adb shell input tap 540 1000; sleep 1; shot 08-player-controls
adb shell input keyevent KEYCODE_BACK; sleep 2
tap_text '^Settings$|^Library$' && sleep 2 && shot 09-after-player

adb logcat -d > "$OUT/logcat.txt"
grep -E "ExoPlayerImpl|PlayerController|MediaCodec.*(video|avc)" "$OUT/logcat.txt" | tail -40 > "$OUT/player-log.txt" || true
if grep -A30 "FATAL EXCEPTION" "$OUT/logcat.txt" | grep -q "$PKG\|io.github.worldtv"; then
  echo "::error::App crashed during smoke test"; grep -A40 "FATAL EXCEPTION" "$OUT/logcat.txt"; exit 1
fi
alive || { echo "::error::App process is not running"; exit 1; }
echo "Smoke test passed"
