#!/bin/zsh
set -euo pipefail
PHYSICS_ROOT="${0:A:h}"
PROJECT_ROOT="${PHYSICS_ROOT:h}"
PHYSICS_OUTPUT="$PROJECT_ROOT/local-only/native-physics"
case "$(uname -m)" in
  arm64) PHYSICS_LIB="$PHYSICS_OUTPUT/macos-arm64"; PHYSICS_TRIPLE=arm64-apple-macosx13.0 ;;
  x86_64) PHYSICS_LIB="$PHYSICS_OUTPUT/macos-x86_64"; PHYSICS_TRIPLE=x86_64-apple-macosx13.0 ;;
  *) print -u2 'Unsupported host'; exit 2 ;;
esac
node "$PHYSICS_ROOT/tests/others_fixture.js"
PHYSICS_SNAPSHOT="$PHYSICS_OUTPUT/tests/snapshots/others"
mkdir -p "$PHYSICS_SNAPSHOT"
PHYSICS_FILES=(SwiftRapierWorld NativeGroundVehicle NativeOtherVehicles NativeVehicleDamage NativeVehicleDamageController NativeVehicleDynamics NativeVehicleForces NativeBikeDynamics NativeFlightDynamics NativeVehicleBuoyancy NativeCharacterMotor NativeRapierCharacterQueries NativeCharacterController)
PHYSICS_SWIFT=()
for source in $PHYSICS_FILES; do
  cp "$PROJECT_ROOT/ios/App/$source.swift" "$PHYSICS_SNAPSHOT/$source.swift"
  PHYSICS_SWIFT+=("$PHYSICS_SNAPSHOT/$source.swift")
done
cp "$PHYSICS_ROOT/tests/others/main.swift" "$PHYSICS_SNAPSHOT/main.swift"
xcrun swiftc -target "$PHYSICS_TRIPLE" -module-cache-path "$PHYSICS_OUTPUT/swift-module-cache" -I "$PHYSICS_ROOT/include" $PHYSICS_SWIFT "$PHYSICS_SNAPSHOT/main.swift" -L "$PHYSICS_LIB" -lzgtasa_native_physics -framework Security -framework CoreFoundation -o "$PHYSICS_OUTPUT/tests/others-integration"
"$PHYSICS_OUTPUT/tests/others-integration" "$PROJECT_ROOT"
