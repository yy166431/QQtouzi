#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build

# Test against Google's actual reader. The iOS dylib uses QQ's runtime and does
# not include or distribute this separately downloaded test dependency.
PROTOBUF_REV=f0dc78d7e6e331b8c6bb2d5283e06aa26883ca7c
if [ ! -f build/protobuf/objectivec/GPBProtocolBuffers.m ]; then
  git init build/protobuf
  git -C build/protobuf remote add origin https://github.com/protocolbuffers/protobuf.git
  git -C build/protobuf fetch --depth 1 origin "$PROTOBUF_REV"
  git -C build/protobuf checkout --detach FETCH_HEAD
fi
test "$(git -C build/protobuf rev-parse HEAD)" = "$PROTOBUF_REV"
MACOS_SDK="$(xcrun --sdk macosx --show-sdk-path)"
xcrun --sdk macosx clang -isysroot "$MACOS_SDK" -fno-objc-arc -O1 \
  -Wno-deprecated-declarations -I build/protobuf/objectivec \
  -c build/protobuf/objectivec/GPBProtocolBuffers.m -o build/ProtobufTests.o
xcrun --sdk macosx clang -isysroot "$MACOS_SDK" -fobjc-arc -fblocks \
  -Wall -Wextra -Werror -I Sources -isystem build/protobuf/objectivec -framework Foundation \
  Sources/QDCore.m Sources/QDWire.m Tests/WireTests.m build/ProtobufTests.o -o build/WireTests
build/WireTests
