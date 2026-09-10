#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
verification_binary=$(mktemp -t bendmac-tests)
trap 'rm -f "$verification_binary"' EXIT
xcrun swiftc BendMac/BendMath.swift Tests/main.swift -o "$verification_binary"
"$verification_binary"
app_path="$PWD/build/Build/Products/Release/BendMac.app"
codesign --verify --deep --strict "$app_path"
"$app_path/Contents/MacOS/BendMac" --sensor-check
"$app_path/Contents/MacOS/BendMac" --render-proof verification/frames
if command -v ffmpeg >/dev/null; then
  ffmpeg -y -hide_banner -loglevel error -framerate 30 -i verification/frames/frame-%03d.png -c:v libx264 -pix_fmt yuv420p -crf 18 verification/fold-preview.mp4
fi
