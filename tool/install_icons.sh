#!/usr/bin/env bash
# Scales the day and night layers from tool/render_icons_test.dart into Android's density folders
# (night ones go to the -night folders, used when the phone is in dark mode).
set -euo pipefail
cd "$(dirname "$0")/.."
RES=android/app/src/main/res
for mode in day night; do
  suffix=$([ "$mode" = night ] && echo "-night" || echo "")
  for pair in mdpi:1 hdpi:1.5 xhdpi:2 xxhdpi:3 xxxhdpi:4; do
    d=${pair%%:*}; f=${pair##*:}
    layer=$(python3 -c "print(round(108*$f))"); icon=$(python3 -c "print(round(48*$f))")
    mkdir -p "$RES/drawable$suffix-$d" "$RES/mipmap$suffix-$d"
    for l in background foreground monochrome; do
      sips -z "$layer" "$layer" "build/icons/$mode/$l.png" --out "$RES/drawable$suffix-$d/ic_launcher_$l.png" >/dev/null
    done
    sips -z "$icon" "$icon" "build/icons/$mode/legacy.png" --out "$RES/mipmap$suffix-$d/ic_launcher.png" >/dev/null
  done
done
echo "Icons installed (day + night). Play Store image: build/icons/day/playstore.png"
