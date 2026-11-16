# Transport source provenance

Upstream: [SA-MP-Android/SA-MP-Pilot](https://github.com/SA-MP-Android/SA-MP-Pilot)
at commit `aa8c7971d2f3c8762a9f20c9ef35b42d5927a768`.
The actual repository's Apache2.0 LICENSE and NOTICE were inspected before
copying. This extraction retains both. No other upstream module is imported.

Imported paths, relative to that revision:

- `internal/raknet/bitstream.go`
- `internal/raknet/frame.go`
- `internal/raknet/conn.go`
- `internal/raknet/rpc.go`
- `internal/raknet/samp_cipher.go`
- `internal/raknet/bitstream_test.go`
- `internal/raknet/frame_test.go`
- `internal/raknet/conn_test.go`
- `internal/raknet/samp_cipher_test.go`

All are preserved verbatim except `conn.go`. It has a prominent modification
notice and its read poll is10ms instead of100ms, to keep outgoing native input
from stalling when the server sends few messages. The independent actual UDP
latency regression covers that change. The module path/build wrapper is new.
The bridge additionally supplies a reliable internal heartbeat; upstream
server-originated ping/pong and reliability logic remain in the transport.

The extraction excludes the headless application's artificial walking/aim,
client-check emulation, GPCI/account state, frontend and plugin execution.
Authentication, RPCs, text codecs, entities and native input remain explicit
application responsibilities. In particular, the upstream domain's0.3.DL
version choice is not evidence of a custom model download/import pipeline.

Other evaluated references were not imported:

- Newmcpe/RakClient tree `6ef94b502d4a3bec3f21c318ced731a0131276f4`
  advertises WTFPL. Its auth table states it is copied verbatim from the
  separate open.mp RakNet fork; that fork's redistribution permission was
  not established by the inspected files. Its root workspace also contains
  a machine-local Recast dependency. No Rust source from it is used here.
- Knogle/libsamp tree `ba17472211ee60b211d5b564f8150a0e80367177`
  has an MIT application license but explicitly does not relicense its
  Knogle/RakNet submodule, which carries historical RakNet2.52 notices.
  The Windows/GTA-bound implementation is not part of this extraction.
- No leaked SA-MP implementation, original SA-MP executable, game assets,
  ReSA binary or ReSA engine code is included.

The generated libraries include the Go runtime and standard library. The
official [Go BSD license](https://github.com/golang/go/blob/master/LICENSE),
inspected blob `2a7cf70da6e498df9c11ab6a5eaa2ddd7af34da4`, is reproduced here.
