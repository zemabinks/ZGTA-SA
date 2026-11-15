#!/bin/zsh
set -eu
cd "${0:A:h}"
node smoke_vehicle_audio.js
mkdir -p local-only/vehicle-audio-fixtures/build
cp ios/App/NativeVehicleAudioDynamics.swift local-only/vehicle-audio-fixtures/build/NativeVehicleAudioDynamics.swift
xcrun swiftc -module-cache-path local-only/radio-fixtures/build/module-cache -O local-only/vehicle-audio-fixtures/build/NativeVehicleAudioDynamics.swift native-physics/tests/vehicle_audio/main.swift -o local-only/vehicle-audio-fixtures/build/road
local-only/vehicle-audio-fixtures/build/road "$PWD/local-only/vehicle-audio-fixtures/road.json"
xcrun swiftc -module-cache-path local-only/radio-fixtures/build/module-cache -O local-only/vehicle-audio-fixtures/build/NativeVehicleAudioDynamics.swift native-physics/tests/vehicle_audio_aux/main.swift -o local-only/vehicle-audio-fixtures/build/auxiliary
local-only/vehicle-audio-fixtures/build/auxiliary "$PWD/local-only/vehicle-audio-fixtures/auxiliary.json"
