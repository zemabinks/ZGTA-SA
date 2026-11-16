#!/bin/zsh
set -euo pipefail
PHYSICS_ROOT="${0:A:h}"
PROJECT_ROOT="${PHYSICS_ROOT:h}"
PHYSICS_OUTPUT="$PROJECT_ROOT/local-only/native-physics"
case "$(uname -m)" in
  arm64) PHYSICS_LIB="$PHYSICS_OUTPUT/macos-arm64"; PHYSICS_TRIPLE=arm64-apple-macosx13.0 ;;
  x86_64) PHYSICS_LIB="$PHYSICS_OUTPUT/macos-x86_64"; PHYSICS_TRIPLE=x86_64-apple-macosx13.0 ;;
  *) exit 2 ;;
esac
node "$PHYSICS_ROOT/tests/rotation_fixture.js"
PHYSICS_SNAPSHOT="$PHYSICS_OUTPUT/tests/snapshots/rotation"
mkdir -p "$PHYSICS_SNAPSHOT"
cp "$PROJECT_ROOT/ios/App/SwiftRapierWorld.swift" "$PHYSICS_ROOT/tests/rotation/main.swift" "$PHYSICS_SNAPSHOT/"
xcrun swiftc -target "$PHYSICS_TRIPLE" -module-cache-path "$PHYSICS_OUTPUT/swift-module-cache" -I "$PHYSICS_ROOT/include" "$PHYSICS_SNAPSHOT/SwiftRapierWorld.swift" "$PHYSICS_SNAPSHOT/main.swift" -L "$PHYSICS_LIB" -lzgtasa_native_physics -framework Security -framework CoreFoundation -o "$PHYSICS_OUTPUT/tests/browser-rotation"
"$PHYSICS_OUTPUT/tests/browser-rotation" "$PROJECT_ROOT/local-only/physics-fixtures/browser-rotation.json"
