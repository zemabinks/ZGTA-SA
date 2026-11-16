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
PHYSICS_SNAPSHOT="$PHYSICS_OUTPUT/tests/snapshots/vehicle"
mkdir -p "$PHYSICS_SNAPSHOT"
cp "$PROJECT_ROOT/ios/App/SwiftRapierWorld.swift" "$PROJECT_ROOT/ios/App/NativeVehicleDynamics.swift" "$PROJECT_ROOT/ios/App/NativeVehicleForces.swift" "$PROJECT_ROOT/ios/App/NativeFlightDynamics.swift" "$PROJECT_ROOT/ios/App/NativeVehicleBuoyancy.swift" "$PHYSICS_ROOT/tests/vehicle/main.swift" "$PHYSICS_SNAPSHOT/"
xcrun swiftc -target "$PHYSICS_TRIPLE" -module-cache-path "$PHYSICS_OUTPUT/swift-module-cache" -I "$PHYSICS_ROOT/include" "$PHYSICS_SNAPSHOT/SwiftRapierWorld.swift" "$PHYSICS_SNAPSHOT/NativeVehicleDynamics.swift" "$PHYSICS_SNAPSHOT/NativeVehicleForces.swift" "$PHYSICS_SNAPSHOT/NativeFlightDynamics.swift" "$PHYSICS_SNAPSHOT/NativeVehicleBuoyancy.swift" "$PHYSICS_SNAPSHOT/main.swift" -L "$PHYSICS_LIB" -lzgtasa_native_physics -framework Security -framework CoreFoundation -o "$PHYSICS_OUTPUT/tests/vehicle-integration"
"$PHYSICS_OUTPUT/tests/vehicle-integration" "$PROJECT_ROOT/local-only/physics-fixtures/vehicle-dynamics.json" "$PHYSICS_OUTPUT/tests/vehicle-integration.json"
