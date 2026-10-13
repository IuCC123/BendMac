#!/bin/zsh
# Stresses how the overlay releases captured frames on the GPU; draws nothing on screen.
set -euo pipefail
cd "${0:A:h}/.."
verification_binary=$(mktemp -t bendmac-texture-tests)
trap 'rm -f "$verification_binary"' EXIT
xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -parse-as-library BendMac/Renderer.swift BendMac/BendMath.swift Tests/TextureCacheRegression.swift -o "$verification_binary"
"$verification_binary"
