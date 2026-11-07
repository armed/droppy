#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
config="${1:-release}"
app="$root/.build/Droppy.app"

if [ ! -d "$root/Vendor/GhosttyKit.xcframework" ] || [ ! -d "$root/Vendor/share" ] || [ ! -f "$root/Vendor/share/droppy/config.template" ]; then
  echo "Vendor/ is incomplete; run scripts/build-ghostty.sh first" >&2
  exit 1
fi

cd "$root"
flags=()
[ "$config" = release ] && flags=(-Xswiftc -Osize)
swift build -c "$config" ${flags[@]+"${flags[@]}"}
bin="$(swift build -c "$config" --show-bin-path)/Droppy"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Droppy"
[ "$config" = release ] && strip -x "$app/Contents/MacOS/Droppy"
cp -R Vendor/share/terminfo "$app/Contents/Resources/"
cp -R Vendor/share/ghostty "$app/Contents/Resources/"
cp Vendor/share/droppy/config.template "$app/Contents/Resources/"
cp Resources/AppIcon.icns Resources/TrayIcon.png "Resources/TrayIcon@2x.png" "$app/Contents/Resources/"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Droppy</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>dev.droppy.Droppy</string>
  <key>CFBundleName</key><string>Droppy</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$app"
echo "built $app"
