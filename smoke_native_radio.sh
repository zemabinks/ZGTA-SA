#!/bin/zsh
set -eu
cd "${0:A:h}"
node smoke_native_radio.js
mkdir -p local-only/radio-fixtures/build
xcrun swiftc -module-cache-path local-only/radio-fixtures/build/module-cache -O ios/App/NativeRadioProgram.swift native-physics/tests/radio/main.swift -o local-only/radio-fixtures/build/radio-program
local-only/radio-fixtures/build/radio-program "$PWD/local-only/radio-fixtures"
