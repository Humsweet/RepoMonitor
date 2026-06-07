#!/bin/bash
# Regenerate all app icon assets from the lucide "folder-git-2" glyph.
#
# Source of truth for the glyph is the official lucide SVG path data, embedded
# verbatim in appicon.svg / glyph.svg (only transformed/recolored, never
# redrawn). Re-run this after editing those SVGs.
#
# Requires: rsvg-convert (brew install librsvg), iconutil (ships with macOS).
set -e
cd "$(dirname "$0")"

echo "Building AppIcon.iconset…"
rm -rf AppIcon.iconset && mkdir AppIcon.iconset
gen() { rsvg-convert -w "$1" -h "$1" appicon.svg -o "AppIcon.iconset/$2"; }
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
gen 1024 icon_512x512@2x.png

iconutil -c icns AppIcon.iconset -o AppIcon.icns
rm -rf AppIcon.iconset
echo "✓ AppIcon.icns"

echo "Building in-app glyph templates…"
rsvg-convert -w 32 -h 32 glyph.svg -o AppGlyph.png
rsvg-convert -w 64 -h 64 glyph.svg -o AppGlyph@2x.png
rsvg-convert -w 96 -h 96 glyph.svg -o AppGlyph@3x.png
echo "✓ AppGlyph.png / @2x / @3x"

# Also refresh the Xcode asset catalog (used only by xcodebuild; bundle.sh
# consumes AppIcon.icns directly).
ASSET="../../RepoMonitor/Assets.xcassets/AppIcon.appiconset"
if [ -d "$ASSET" ]; then
  gen2() { rsvg-convert -w "$1" -h "$1" appicon.svg -o "$ASSET/$2"; }
  gen2 16   icon_16.png
  gen2 32   icon_16@2x.png
  gen2 32   icon_32.png
  gen2 64   icon_32@2x.png
  gen2 128  icon_128.png
  gen2 256  icon_128@2x.png
  gen2 256  icon_256.png
  gen2 512  icon_256@2x.png
  gen2 512  icon_512.png
  gen2 1024 icon_512@2x.png
  echo "✓ Refreshed asset catalog PNGs"
fi
