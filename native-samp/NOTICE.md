SA-MP-Pilot
Copyright 2026 SA-MP Android

This product is licensed under the Apache License, Version 2.0.

## ZGTA SA extraction and modifications

The files in `internal/raknet` except `native_latency_test.go` are from
SA-MP-Android/SA-MP-Pilot, commit aa8c7971d2f3c8762a9f20c9ef35b42d5927a768.
Their Apache2.0 license and upstream copyright notice are preserved here.
`conn.go` is modified: read polling is10ms instead of100ms, avoiding a quiet
server delaying native outgoing input. The public source excludes the Pilot
frontend, bot movement, account storage and client-check emulation.

`bridge.go`, `main.go`, `bridge_test.go`, `native_latency_test.go`, the C API
header/module, C ABI test and build script are independent ZGTA SA additions
under the repository's AGPL-3.0-only license. The bridge adds cancellation,
bounded event/send ownership and a reliable internal RakNet heartbeat after
transport acceptance.

Generated libraries include the Go runtime and standard library, whose BSD
license is reproduced in `LICENSE-GO.md`. They are built locally and are not
tracked in the public source release. No original game assets or SA-MP binary
files are included. No transport implementation from open.mp's legacy RakNet
fork, Knogle/RakNet or RakClient is incorporated.

## Native text codec adaptation

`ios/App/NativeSAMPTextCodec.swift` independently integrates a Swift adaptation
of Pilot `internal/samp/huffman.go`, including its English frequency table and
original tie ordering, from the same pinned revision. It retains the Apache2.0
copyright/license notice. Bounds and Foundation text-codec integration are
ZGTA modifications. The C++ `hello` fixture in the UI regression originates in
Pilot `internal/samp/huffman_test.go` at that same revision. No game fonts or
original game resources are included in those sources.
