#!/usr/bin/env bash
# Emulator smoke test: install, launch, visit screens, start playback, capture screenshots.
# Fails if the app process dies or logcat shows a fatal exception from the app.
set -uo pipefail
APK="$1"
OUT="${2:-smoke}"
PKG=io.github.worldtv.android
mkdir -p "$OUT"

shot() { adb exec-out screencap -p > "$OUT/$1.png"; echo "screenshot $1"; }
dump() {
  for _ in 1 2 3 4; do
    adb shell rm -f /sdcard/ui.xml
    adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
    adb shell cat /sdcard/ui.xml > "$OUT/ui.xml" 2>/dev/null
    grep -q "<node" "$OUT/ui.xml" && return 0
    sleep 2
  done
  echo "uiautomator dump failed"
}
texts() { dump; grep -o 'text="[^"]\+"' "$OUT/ui.xml" | head -40 | tr '\n' ' '; echo; }
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
tap_text '^Search$' && sleep 2 && adb shell input text "news" && sleep 3 && shot 04-search && adb shell input keyevent KEYCODE_BACK && sleep 1
tap_text '^Guide$' && sleep 2 && shot 05-guide
tap_text '^Library$' && sleep 2 && shot 06-library
tap_text '^Home$' && sleep 4
echo "home texts: $(texts)"
tap_text '^LIVE$' || tap_text 'Popular now'
sleep 25; shot 07-player
echo "player texts: $(texts)"
adb shell input tap 540 1000; sleep 1; shot 08-player-controls
adb shell input keyevent KEYCODE_BACK; sleep 2
tap_text '^Settings$|^Library$' && sleep 2 && shot 09-after-player

adb logcat -d > "$OUT/logcat.txt"
grep -E "ExoPlayerImpl|PlayerController|MediaCodec.*(video|avc)" "$OUT/logcat.txt" | tail -40 > "$OUT/player-log.txt" || true
if grep -A30 "FATAL EXCEPTION" "$OUT/logcat.txt" | grep -q "$PKG\|io.github.worldtv"; then
  echo "::error::App crashed during smoke test"; grep -A40 "FATAL EXCEPTION" "$OUT/logcat.txt"; exit 1
fi
alive || { echo "::error::App process is not running"; exit 1; }
tap_text '^Settings$' || true
# Print small JPEG previews into the log (artifacts are not always downloadable).
python3 -m pip install --quiet --user pillow >/dev/null 2>&1 || true
for f in "$OUT"/*.png; do
  python3 -c "import sys; from PIL import Image; im=Image.open(sys.argv[1]).convert('RGB'); im.thumbnail((432, 960)); im.save(sys.argv[2], quality=60)" "$f" "${f%.png}.jpg" || continue
  echo "===IMG $(basename "${f%.png}")==="; base64 -w0 "${f%.png}.jpg"; echo; echo "===END==="
done
echo "--- player log ---"; cat "$OUT/player-log.txt"
echo "Smoke test passed"
