#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build

MACOS_SDK="$(xcrun --sdk macosx --show-sdk-path)"
xcrun --sdk macosx clang -isysroot "$MACOS_SDK" -fobjc-arc -fblocks \
  -Wall -Wextra -Werror -I Sources -framework Foundation \
  Sources/QDCore.m Tests/CoreTests.m -o build/CoreTests
build/CoreTests

IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang -isysroot "$IOS_SDK" -target arm64-apple-ios15.0 \
  -dynamiclib -fobjc-arc -fblocks -fvisibility=hidden -O2 \
  -Wall -Wextra -Werror -I Sources -framework Foundation -framework UIKit \
  -Wl,-install_name,@rpath/QQtouzi.dylib \
  -Wl,-compatibility_version,1.0 -Wl,-current_version,0.2.0 \
  Sources/QDCore.m Sources/QQDice.m -o build/QQtouzi.dylib
codesign --force --sign - --timestamp=none build/QQtouzi.dylib
codesign --verify --strict build/QQtouzi.dylib
xcrun lipo build/QQtouzi.dylib -verify_arch arm64
file build/QQtouzi.dylib
xcrun otool -L build/QQtouzi.dylib
shasum -a 256 build/QQtouzi.dylib > build/SHA256SUMS.txt
cp README.md build/README.md
