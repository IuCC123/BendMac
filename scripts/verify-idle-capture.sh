#!/bin/zsh
# Requires a logged-in Mac and Screen Recording permission. Displays no overlay.
set -euo pipefail
cd "${0:A:h}/.."
verification_binary=$(mktemp -t bendmac-idle-capture-tests)
trap 'rm -f "$verification_binary"' EXIT
xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -parse-as-library BendMac/AppModel.swift BendMac/DesktopCapture.swift BendMac/BendMath.swift Tests/IdleCaptureRegression.swift -o "$verification_binary"
"$verification_binary"
