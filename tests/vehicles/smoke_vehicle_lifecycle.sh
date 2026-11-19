#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h:h}"
PHYSICS_OUTPUT="$PROJECT_ROOT/local-only/native-physics"
case "$(uname -m)" in
  arm64) PHYSICS_LIB="$PHYSICS_OUTPUT/macos-arm64"; PHYSICS_TRIPLE=arm64-apple-macosx13.0 ;;
  x86_64) PHYSICS_LIB="$PHYSICS_OUTPUT/macos-x86_64"; PHYSICS_TRIPLE=x86_64-apple-macosx13.0 ;;
  *) exit 2 ;;
esac
PHYSICS_SNAPSHOT="$PHYSICS_OUTPUT/tests/snapshots/vehicle-lifecycle"
mkdir -p "$PHYSICS_SNAPSHOT"
PHYSICS_FILES=(SwiftRapierWorld NativeGroundVehicle NativeOtherVehicles NativeUnattendedVehicle NativeVehicleDamage NativeVehicleDamageController NativeVehicleDynamics NativeVehicleForces NativeBikeDynamics NativeFlightDynamics NativeVehicleBuoyancy NativeTrainDynamics)
PHYSICS_SWIFT=()
for source in $PHYSICS_FILES; do
  cp "$PROJECT_ROOT/ios/App/$source.swift" "$PHYSICS_SNAPSHOT/$source.swift"
  PHYSICS_SWIFT+=("$PHYSICS_SNAPSHOT/$source.swift")
done
cp "$PROJECT_ROOT/tests/vehicles/smoke_vehicle_lifecycle.swift" "$PHYSICS_SNAPSHOT/main.swift"
env -u SDKROOT xcrun swiftc -parse-as-library -whole-module-optimization -target "$PHYSICS_TRIPLE" -module-cache-path "$PHYSICS_OUTPUT/swift-module-cache" -I "$PROJECT_ROOT/native-physics/include" $PHYSICS_SWIFT "$PHYSICS_SNAPSHOT/main.swift" -L "$PHYSICS_LIB" -lzgtasa_native_physics -framework Security -framework CoreFoundation -o "$PHYSICS_OUTPUT/tests/vehicle-lifecycle"
"$PHYSICS_OUTPUT/tests/vehicle-lifecycle" "$PROJECT_ROOT"
