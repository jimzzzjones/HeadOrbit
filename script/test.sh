#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
mkdir -p build/module-cache
sources=(HeadOrbit/Actions/*.swift HeadOrbit/Motion/*.swift HeadOrbit/Overlay/*.swift HeadOrbit/UI/*.swift)
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$ROOT_DIR/build/module-cache" \
    "${sources[@]}" Tests/ReplayTests.swift -o build/replay-tests
build/replay-tests
