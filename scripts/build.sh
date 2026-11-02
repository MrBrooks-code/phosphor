#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration="${1:-release}"
swift build -c "$configuration"
product="$(swift build -c "$configuration" --show-bin-path)"
app="$PWD/build/Phosphor.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$product/Phosphor" "$app/Contents/MacOS/Phosphor"
cp -R "$product/Phosphor_PhosphorApp.bundle" "$app/Contents/Resources/"
cp scripts/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
print "$app"
