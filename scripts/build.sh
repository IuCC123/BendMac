#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
xcodegen generate
xcodebuild -project BendMac.xcodeproj -scheme BendMac -configuration Release -derivedDataPath build CODE_SIGN_IDENTITY=- build
