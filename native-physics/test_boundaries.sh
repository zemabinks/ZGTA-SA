#!/bin/zsh
set -euo pipefail
PHYSICS_ROOT="${0:A:h}"
PROJECT_ROOT="${PHYSICS_ROOT:h}"
PHYSICS_OUTPUT="$PROJECT_ROOT/local-only/native-physics"
case "$(uname -m)" in
  arm64) PHYSICS_LIB="${PHYSICS_HOST_LIB:-$PHYSICS_OUTPUT/macos-arm64}" ;;
  x86_64) PHYSICS_LIB="${PHYSICS_HOST_LIB:-$PHYSICS_OUTPUT/macos-x86_64}" ;;
  *) exit 2 ;;
esac
node "$PHYSICS_ROOT/tests/mass_fixture.js"
node "$PHYSICS_ROOT/tests/friction_fixture.js"
PHYSICS_SNAPSHOT="$PHYSICS_OUTPUT/tests/snapshots/boundaries"
mkdir -p "$PHYSICS_SNAPSHOT"
cp "$PROJECT_ROOT/ios/App/SwiftRapierWorld.swift" "$PHYSICS_ROOT/tests/boundaries/main.swift" "$PHYSICS_SNAPSHOT/"
xcrun swiftc -module-cache-path "$PHYSICS_OUTPUT/swift-module-cache" -I "$PHYSICS_ROOT/include" -O "$PHYSICS_SNAPSHOT/SwiftRapierWorld.swift" "$PHYSICS_SNAPSHOT/main.swift" -L "$PHYSICS_LIB" -lzgtasa_native_physics -framework Security -framework CoreFoundation -o "$PHYSICS_OUTPUT/tests/boundaries"
"$PHYSICS_OUTPUT/tests/boundaries" "$PHYSICS_OUTPUT/tests"
