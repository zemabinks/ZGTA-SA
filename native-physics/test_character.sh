#!/bin/zsh
set -euo pipefail
PHYSICS_ROOT="${0:A:h}"
PROJECT_ROOT="${PHYSICS_ROOT:h}"
PHYSICS_OUTPUT="$PROJECT_ROOT/local-only/native-physics"
case "$(uname -m)" in
  arm64) PHYSICS_LIB="${PHYSICS_HOST_LIB:-$PHYSICS_OUTPUT/macos-arm64}"; PHYSICS_TRIPLE=arm64-apple-macosx13.0 ;;
  x86_64) PHYSICS_LIB="${PHYSICS_HOST_LIB:-$PHYSICS_OUTPUT/macos-x86_64}"; PHYSICS_TRIPLE=x86_64-apple-macosx13.0 ;;
  *) print -u2 'Unsupported host'; exit 2 ;;
esac
node "$PROJECT_ROOT/tests/movement/smoke_character_motor.js"
PHYSICS_SNAPSHOT="$PHYSICS_OUTPUT/tests/snapshots/character-integration"
mkdir -p "$PHYSICS_SNAPSHOT"
cp "$PROJECT_ROOT/ios/App/SwiftRapierWorld.swift" "$PROJECT_ROOT/ios/App/NativeCharacterMotor.swift" "$PROJECT_ROOT/ios/App/NativeRapierCharacterQueries.swift" "$PHYSICS_ROOT/tests/character/main.swift" "$PHYSICS_SNAPSHOT/"
xcrun swiftc -target "$PHYSICS_TRIPLE" -module-cache-path "$PHYSICS_OUTPUT/swift-module-cache" -I "$PHYSICS_ROOT/include" "$PHYSICS_SNAPSHOT/SwiftRapierWorld.swift" "$PHYSICS_SNAPSHOT/NativeCharacterMotor.swift" "$PHYSICS_SNAPSHOT/NativeRapierCharacterQueries.swift" "$PHYSICS_SNAPSHOT/main.swift" -L "$PHYSICS_LIB" -lzgtasa_native_physics -framework Security -framework CoreFoundation -o "$PHYSICS_OUTPUT/tests/character-integration"
"$PHYSICS_OUTPUT/tests/character-integration" "$PROJECT_ROOT/local-only/physics-fixtures/character-motor.json" "$PHYSICS_OUTPUT/tests/character-integration.json"
