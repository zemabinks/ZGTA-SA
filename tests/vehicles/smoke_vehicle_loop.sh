#!/bin/zsh
set -eu
cd "${0:A:h:h:h}"
mkdir -p local-only/vehicle-audio-fixtures/loop-build
for source in NativeRateAudio NativeVehicleAudioDynamics NativeVehicleAudioSpatial NativeVehicleLoopAudio; do
  cp "ios/App/$source.swift" "local-only/vehicle-audio-fixtures/loop-build/$source.swift"
done
xcrun swiftc -module-cache-path local-only/radio-fixtures/build/module-cache -O local-only/vehicle-audio-fixtures/loop-build/*.swift native-physics/tests/vehicle_loop/main.swift -o local-only/vehicle-audio-fixtures/loop-build/verify
if [[ "${1:-}" != "--compile-only" ]]; then
  local-only/vehicle-audio-fixtures/loop-build/verify
fi
