#!/bin/zsh
set -eu
cd "${0:A:h:h:h}"
node tests/audio/smoke_vehicle_audio_spatial.js
mkdir -p local-only/vehicle-audio-fixtures/spatial-build
cp ios/App/NativeVehicleAudioSpatial.swift local-only/vehicle-audio-fixtures/spatial-build/
xcrun swiftc -module-cache-path local-only/radio-fixtures/build/module-cache -O local-only/vehicle-audio-fixtures/spatial-build/NativeVehicleAudioSpatial.swift native-physics/tests/vehicle_spatial/main.swift -o local-only/vehicle-audio-fixtures/spatial-build/verify
local-only/vehicle-audio-fixtures/spatial-build/verify "$PWD/local-only/vehicle-audio-fixtures/spatial.json"
