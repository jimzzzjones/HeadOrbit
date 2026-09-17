#!/bin/zsh
# Generate the Xcode project and build. Output: build/Build/Products/Debug/HeadOrbit.app
set -euo pipefail
cd "$(dirname "$0")"
xcodegen generate
xcodebuild -project HeadOrbit.xcodeproj -scheme HeadOrbit -configuration Debug \
  -derivedDataPath build build
echo "→ build/Build/Products/Debug/HeadOrbit.app"
