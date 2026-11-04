#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration="${1:-release}"
swift build -c "$configuration"
product="$(swift build -c "$configuration" --show-bin-path)"
app="$PWD/build/Phosphor.app"
if [[ "${2:-}" == "--scene-development" ]]; then
    app="$PWD/build/Phosphor Scenes.app"
fi
if [[ "${2:-}" == "--response-development" ]]; then
    app="$PWD/build/Phosphor Response.app"
fi
if [[ "${2:-}" == "--v2-development" ]]; then
    app="$PWD/build/Phosphor V2.app"
fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$product/Phosphor" "$app/Contents/MacOS/Phosphor"
cp -R "$product/Phosphor_PhosphorApp.bundle" "$app/Contents/Resources/"
cp scripts/Info.plist "$app/Contents/Info.plist"
# Give scene previews their own launch identity and preferences.
if [[ "${2:-}" == "--scene-development" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.mrbrooks.phosphor.scenes-de8f" "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName Phosphor Scenes" "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Phosphor Scenes" "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :PhosphorSyntheticGallery bool true" "$app/Contents/Info.plist"
fi
# Keep actual capture enabled and preferences separate for the response preview.
if [[ "${2:-}" == "--response-development" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.mrbrooks.phosphor.response-2d5d" "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName Phosphor Response" "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Phosphor Response" "$app/Contents/Info.plist"
fi
# V2 uses real capture by default and never reads the production desk.
if [[ "${2:-}" == "--v2-development" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.mrbrooks.phosphor.v2-ae8b" "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName Phosphor V2" "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Phosphor V2" "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :PhosphorSceneV2 bool true" "$app/Contents/Info.plist"
fi
codesign --force --sign - "$app"
print "$app"
