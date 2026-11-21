#!/bin/bash
# Usage: ./build.sh "path/to/RTL Bench.app" [path/to/extracted/oss-cad-suite]
set -euo pipefail
src=$(cd "$(dirname "$0")" && pwd)
app=${1:-"$src/../RTL Bench.app"}
[[ "$app" = *.app ]] || { echo 'Specify a destination ending in .app' >&2; exit 2; }
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
app=$(cd "$app" && pwd)
cache=$(mktemp -d)
trap 'rm -rf "$cache"' EXIT
# Some Command Line Tools installations omit the newer SDK’s SwiftUI macro plug-in.
sdk=${SDKROOT:-$(xcrun --sdk macosx26.5 --show-sdk-path 2>/dev/null || xcrun --sdk macosx --show-sdk-path)}
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos26.0 -sdk "$sdk" \
    -module-cache-path "$cache" "$src"/*.swift -o "$app/Contents/MacOS/RTLBench"
cp "$src/Info.plist" "$app/Contents/Info.plist"
cp "$src/RTLBench.icns" "$app/Contents/Resources/"
if [[ $# -ge 2 ]]; then "$src/embed-tools.sh" "$2" "$app"; fi
codesign --force --sign - "$app"
codesign --verify --strict "$app"
