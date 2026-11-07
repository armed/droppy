#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
renderer="${ICON_RENDERER:-$HOME/.claude/plugins/cache/logo-design-skill/logo-design/1.4.4/skills/logo-design/scripts/render_png.py}"
src="$root/Resources/icon"

if [ ! -f "$renderer" ]; then
  echo "render_png.py not found; set ICON_RENDERER to its path" >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The renderer names its output after the SVG, so each size goes through its own directory.
render() {
  local svg="$1" size="$2" out="$3"
  local dir="$work/r$size-$(basename "$svg" .svg)"
  mkdir -p "$dir"
  python3 "$renderer" "$svg" --out-dir "$dir" --size "$size" >/dev/null
  cp "$dir/$(basename "$svg" .svg).png" "$out"
}

iconset="$work/AppIcon.iconset"
mkdir -p "$iconset"
# The bolder cut keeps the glyph legible where the full artwork would turn to mush.
render "$src/icon-small.svg" 16 "$iconset/icon_16x16.png"
render "$src/icon-small.svg" 32 "$iconset/icon_16x16@2x.png"
render "$src/icon-small.svg" 32 "$iconset/icon_32x32.png"
render "$src/icon-small.svg" 64 "$iconset/icon_32x32@2x.png"
render "$src/icon.svg" 128 "$iconset/icon_128x128.png"
render "$src/icon.svg" 256 "$iconset/icon_128x128@2x.png"
render "$src/icon.svg" 256 "$iconset/icon_256x256.png"
render "$src/icon.svg" 512 "$iconset/icon_256x256@2x.png"
render "$src/icon.svg" 512 "$iconset/icon_512x512.png"
render "$src/icon.svg" 1024 "$iconset/icon_512x512@2x.png"
iconutil -c icns "$iconset" -o "$root/Resources/AppIcon.icns"

render "$src/tray.svg" 18 "$root/Resources/TrayIcon.png"
render "$src/tray.svg" 36 "$root/Resources/TrayIcon@2x.png"
echo "generated icons in $root/Resources"
