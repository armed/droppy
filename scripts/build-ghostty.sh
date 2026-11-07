#!/usr/bin/env bash
set -euo pipefail

GHOSTTY_TAG="v1.4.0"

root="$(cd "$(dirname "$0")/.." && pwd)"
optimize="${1:-ReleaseFast}"
src="$root/Vendor/src/ghostty"
out="${GHOSTTY_VENDOR_OUT:-$root/Vendor}"

if [ ! -d "$src/.git" ]; then
  git clone --depth 1 --branch "$GHOSTTY_TAG" https://github.com/ghostty-org/ghostty.git "$src"
fi

cd "$src"
actual="$(git describe --tags --exact-match)"
if [ "$actual" != "$GHOSTTY_TAG" ]; then
  echo "expected $GHOSTTY_TAG in $src, found $actual; remove Vendor/src/ghostty" >&2
  exit 1
fi

zig="$(cd "$root" && mise which zig)"
"$zig" build \
  -Demit-xcframework=true \
  -Demit-macos-app=false \
  -Dxcframework-target=native \
  -Doptimize="$optimize"

mkdir -p "$out"
rm -rf "$out/GhosttyKit.xcframework"
cp -R macos/GhosttyKit.xcframework "$out/"
rm -rf "$out/share"
mkdir -p "$out/share/ghostty"
cp -R zig-out/share/terminfo "$out/share/"
cp -R zig-out/share/ghostty/shell-integration "$out/share/ghostty/"
cp -R zig-out/share/ghostty/themes "$out/share/ghostty/"
mkdir -p "$out/share/droppy"
python3 "$root/scripts/generate-config-template.py" \
  zig-out/share/ghostty/doc/ghostty.5.md src/config/Config.zig "$out/share/droppy/config.template"
echo "installed $out/GhosttyKit.xcframework and $out/share"
