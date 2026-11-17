#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p local-only/radio-fixtures/build
xcrun swiftc -module-cache-path local-only/radio-fixtures/build/module-cache -O ios/App/ServerAddress.swift ios/App/NativeRadioProgram.swift ios/App/NativeRadioPCMWindow.swift ios/App/NativeRadioPlayback.swift native-physics/tests/radio_pcm/main.swift -o local-only/radio-fixtures/build/radio-pcm
local-only/radio-fixtures/build/radio-pcm "$PWD/local-only/radio-fixtures/build"
