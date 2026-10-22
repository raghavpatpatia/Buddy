#!/usr/bin/env bash
# Scales the layers from tool/render_icons_test.dart into Android's density folders.
set -euo pipefail
cd "$(dirname "$0")/.."
RES=android/app/src/main/res
for pair in mdpi:1 hdpi:1.5 xhdpi:2 xxhdpi:3 xxxhdpi:4; do
  d=${pair%%:*}; f=${pair##*:}
  layer=$(python3 -c "print(round(108*$f))"); icon=$(python3 -c "print(round(48*$f))")
  for l in background foreground monochrome; do
    sips -z "$layer" "$layer" "build/icons/$l.png" --out "$RES/drawable-$d/ic_launcher_$l.png" >/dev/null
  done
  sips -z "$icon" "$icon" build/icons/legacy.png --out "$RES/mipmap-$d/ic_launcher.png" >/dev/null
done
echo "Icons installed. Play Store image: build/icons/playstore.png"
