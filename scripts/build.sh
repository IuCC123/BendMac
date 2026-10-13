#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
xcodegen generate
# A generic destination builds the Intel slice too; without it, xcodebuild targets only this Mac.
xcodebuild -project BendMac.xcodeproj -scheme BendMac -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build CODE_SIGN_IDENTITY=- build
