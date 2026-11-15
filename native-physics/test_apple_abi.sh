#!/bin/zsh
set -euo pipefail
PHYSICS_ROOT="${0:A:h}"
PROJECT_ROOT="${PHYSICS_ROOT:h}"
PHYSICS_OUTPUT="$PROJECT_ROOT/local-only/native-physics"
PHYSICS_SNAPSHOT="$PHYSICS_OUTPUT/tests/snapshots/apple-abi"
mkdir -p "$PHYSICS_SNAPSHOT"
cp "$PROJECT_ROOT/ios/App/SwiftRapierWorld.swift" "$PHYSICS_SNAPSHOT/"
link_target() {
  local physics_triple="$1" physics_sdk="$2" physics_directory="$3"
  local physics_sdk_path="$(xcrun --sdk "$physics_sdk" --show-sdk-path)"
  xcrun --sdk "$physics_sdk" swiftc -parse-as-library -emit-library -module-name NativePhysicsABI -target "$physics_triple" -sdk "$physics_sdk_path" -module-cache-path "$PHYSICS_OUTPUT/swift-module-cache" -I "$PHYSICS_ROOT/include" "$PHYSICS_SNAPSHOT/SwiftRapierWorld.swift" -L "$PHYSICS_OUTPUT/$physics_directory" -lzgtasa_native_physics -framework Security -framework CoreFoundation -o "$PHYSICS_OUTPUT/tests/abi-$physics_triple.dylib"
  print "PASS: native Swift/C/Rust ABI linked for $physics_triple"
}
link_target arm64-apple-ios16.0 iphoneos ios-device
link_target arm64-apple-ios16.0-simulator iphonesimulator ios-simulator
link_target x86_64-apple-ios16.0-simulator iphonesimulator ios-simulator
link_target arm64-apple-macosx13.0 macosx macos-arm64
link_target x86_64-apple-macosx13.0 macosx macos-x86_64
