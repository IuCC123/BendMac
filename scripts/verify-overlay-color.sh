#!/bin/zsh
# Requires a built app, logged-in desktop and Screen Recording permission.
# Briefly shows a color chart and a slight fold; no screen content is saved.
set -euo pipefail
cd "${0:A:h}/.."
verification_directory=$(mktemp -d -t bendmac-color-tests)
trap 'rm -rf "$verification_directory"' EXIT
# BendMac excludes its own app from capture, so the chart runs from a second bundle.
for name in BendMacColorTests BendMacColorChart; do
  mkdir -p "$verification_directory/$name.app/Contents/MacOS" "$verification_directory/$name.app/Contents/Resources"
  cat > "$verification_directory/$name.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$name</string>
<key>CFBundleIdentifier</key><string>local.jamie.$name</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
done
verification_app="$verification_directory/BendMacColorTests.app"
chart_executable="$verification_directory/BendMacColorChart.app/Contents/MacOS/BendMacColorChart"
cp build/Build/Products/Release/BendMac.app/Contents/Resources/default.metallib "$verification_app/Contents/Resources/"
xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -parse-as-library \
  BendMac/AppModel.swift BendMac/BendMath.swift BendMac/DesktopCapture.swift \
  BendMac/LidSensor.swift BendMac/Renderer.swift Tests/OverlayColorRegression.swift \
  -o "$verification_app/Contents/MacOS/BendMacColorTests"
cp "$verification_app/Contents/MacOS/BendMacColorTests" "$chart_executable"
"$verification_app/Contents/MacOS/BendMacColorTests" "$chart_executable"
