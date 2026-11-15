#!/bin/zsh
set -euo pipefail
PHYSICS_ROOT="${0:A:h}"
PROJECT_ROOT="${PHYSICS_ROOT:h}"
export RUSTUP_HOME="$PROJECT_ROOT/local-only/toolchains/rustup"
export CARGO_HOME="$PROJECT_ROOT/local-only/toolchains/cargo"
export PATH="$CARGO_HOME/bin:$PATH"
PHYSICS_OUTPUT="$PROJECT_ROOT/local-only/native-physics"
PHYSICS_HOST="$(rustc -vV | sed -n 's/^host: //p')"
case "$PHYSICS_HOST" in
  aarch64-apple-darwin) PHYSICS_LIB="$PHYSICS_OUTPUT/macos-arm64"; PHYSICS_TRIPLE=arm64-apple-macosx13.0 ;;
  x86_64-apple-darwin) PHYSICS_LIB="$PHYSICS_OUTPUT/macos-x86_64"; PHYSICS_TRIPLE=x86_64-apple-macosx13.0 ;;
  *) print -u2 "Unsupported native test host: $PHYSICS_HOST"; exit 2 ;;
esac
if [[ "${PHYSICS_SKIP_BUILD:-0}" != 1 ]]; then "$PHYSICS_ROOT/build.sh" host; fi
mkdir -p "$PHYSICS_OUTPUT/tests"
xcrun clang -target "$PHYSICS_TRIPLE" -I "$PHYSICS_ROOT/include" "$PHYSICS_ROOT/tests/smoke.c" "$PHYSICS_LIB/libzgtasa_native_physics.a" -framework Security -framework CoreFoundation -liconv -o "$PHYSICS_OUTPUT/tests/c-smoke"
"$PHYSICS_OUTPUT/tests/c-smoke"
PHYSICS_SNAPSHOT="$PHYSICS_OUTPUT/tests/snapshots/character"
mkdir -p "$PHYSICS_SNAPSHOT"
cp "$PROJECT_ROOT/ios/App/SwiftRapierWorld.swift" "$PROJECT_ROOT/ios/App/NativeCharacterMotor.swift" "$PROJECT_ROOT/ios/App/NativeRapierCharacterQueries.swift" "$PROJECT_ROOT/ios/App/NativeCharacterController.swift" "$PHYSICS_ROOT/tests/swift/main.swift" "$PHYSICS_SNAPSHOT/"
xcrun swiftc -target "$PHYSICS_TRIPLE" -module-cache-path "$PHYSICS_OUTPUT/swift-module-cache" -I "$PHYSICS_ROOT/include" "$PHYSICS_SNAPSHOT/SwiftRapierWorld.swift" "$PHYSICS_SNAPSHOT/NativeCharacterMotor.swift" "$PHYSICS_SNAPSHOT/NativeRapierCharacterQueries.swift" "$PHYSICS_SNAPSHOT/NativeCharacterController.swift" "$PHYSICS_SNAPSHOT/main.swift" -L "$PHYSICS_LIB" -lzgtasa_native_physics -framework Security -framework CoreFoundation -o "$PHYSICS_OUTPUT/tests/swift-smoke"
"$PHYSICS_OUTPUT/tests/swift-smoke" "$PROJECT_ROOT/local-only/site/game/world/c59.col.bin"
