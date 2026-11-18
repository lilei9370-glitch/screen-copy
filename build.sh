#!/bin/zsh
set -eu
cd -- "${0:A:h}"
app="${1:-$PWD/dist/框选取字.app}"
identity="${CODE_SIGN_IDENTITY:--}"
build=$(mktemp -d "${TMPDIR:-/tmp}/screen-copy-build.XXXXXXXX")
trap 'rm -rf -- "$build"' EXIT
bundle="$build/框选取字.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$bundle/Contents/Library/LaunchAgents"
cp Info.plist "$bundle/Contents/"
cp AppIcon.icns "$bundle/Contents/Resources/"
cp io.github.lilei9370-glitch.screencopy.shortcut.plist "$bundle/Contents/Library/LaunchAgents/"
xcrun swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macos15.0 \
  ScreenCopy.swift Selection.swift TextRecognition.swift PermissionGuide.swift AppShortcut.swift -o "$bundle/Contents/MacOS/ScreenCopy"
xcrun swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macos15.0 \
  ColdCaptureShortcut.swift AppShortcut.swift -o "$bundle/Contents/MacOS/ColdCaptureShortcut"
sign=(--force --sign "$identity")
if [[ "$identity" != "-" ]]; then sign+=(--options runtime --timestamp); fi
codesign "${sign[@]}" "$bundle/Contents/MacOS/ColdCaptureShortcut"
codesign "${sign[@]}" "$bundle"
codesign --verify --deep --strict "$bundle"
mkdir -p "${app:h}"
ditto "$bundle" "$app"
print -r -- "$app"
