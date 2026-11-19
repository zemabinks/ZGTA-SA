# Local compressed radio playback · Core109

This source connects the existing station programme to verified, owner-provided
raw radio packs. It does not distribute recordings or turn raw extraction into
a complete playable installation. The existing programme remains the authority
for station time, piece IDs and `plays` sample counts.

`NativeVehicleRadio` first asks `NativeLocalRadioProvider` for eligible local
stations. That works without the optional development `game/radio/native/index`
response, which is absent from the canonical prepared package. Emergency AA is
station 0; station 13 stays off. User tracks keep their existing separate path.
A truly absent raw radio source permits the development fallback. A present but
invalid source, missing selected station or failed verified pack reports an
error; it does not silently fetch replacement audio. Installed-resource HTTP
fallback remains subject to the existing persistent resolver's fail-closed
policy.

## Catalogue and playback ownership

Catalogue creation reads a lightweight raw receipt and lazily verifies only
`audio/config/StrmPaks.dat` and `audio/config/TrakLkup.dat`. Complete paths match
case-insensitively while retaining receipt spellings. Pack sizes come from the
receipt. Catalogue creation does not open or checksum all audio packs.

The selected session captures source, content and generation identities. Each
new tune/resume reads that descriptor again. The actual selected pack is then
acquired with the same descriptor and a whole-file checksum. The provider
retains the verified lease and an owned descriptor for the entire decoder
lifetime. C creates its own positional-I/O descriptor; creation, preparation and
reads run within the borrowed descriptor's mutation checks.

One utility queue owns all handles and codec work. Limits are two pinned packs,
two prepared decoder handles, one outstanding window and at most 8,000 requested
frames. Each decoder is also subject to the C ABI's independent allocation and
record limits. Retune, exit, interruption or cancellation invalidates pending
requests and queued main completions, cancels an active C call and closes C
state before releasing its descriptors. Store request IDs are reserved before
calling the asynchronous API, so an early callback cannot reinsert an already
completed Request when that API returns. No decoder uses an ISO path or a
second whole-pack copy.

`NativeRadioPlayback` converts bounded interleaved float windows into native
`AVAudioPCMBuffer` instances off main. Mono is duplicated by the decoder. A
recording shorter than its programme piece is padded with silence; a longer
recording is truncated by the programme boundary. The programme counts are not
replaced with decoder lengths.

The station clock continues while verification/decoding is pending. A delayed
completion trims only its elapsed prefix when it still contains the current
sample. A completely stale window is dropped, while the prepared decoder stays
cached for the next request. Failed obsolete assets are marked failed rather
than triggering endless preparation. Generation/ticket checks prevent an old
completion from scheduling into a new station or clearing its pending request.

## Focused verification

Run the public authored-fixture test with existing source-stamped libraries:

```sh
python3 tests/audio/smoke_native_local_radio.py --sdk-check \
  --library-root local-only/native-audio/targets \
  --installer-archive /absolute/path/to/local-only/native-installer/host/libzgtasa_installer.a
```

The command does not build C or import original music. It uses independently
authored mathematical Vorbis recordings, an explicitly injected authored raw
extractor, the actual RawStore/leases/catalogue/C provider, and actual native
PCM buffers. Playback completion and station routing exercise extracted
production methods with explicit audio-sink/lifecycle spies. Apple SDK checks
compile and link device and both Simulator architectures without execution.

It never starts an audio engine, operates a device or Simulator, starts a
service, or makes a retail-runtime/fidelity/performance claim. Full-App build,
actual audible playback, interruptions and installed-mode rendered acceptance
remain separate Root-owned checks.

The final immutable run passed **32,177 authored-fixture/sample checks**.
The actual source compiled and linked for arm64 iOS16, arm64 iOS16 Simulator
and x86_64 iOS16 Simulator. All three links are compile/link evidence only.
A private negative control using the previous actual request-bookkeeping
methods fails the new completion-before-return assertion as intended.


The complete109 Debug App subsequently builds for Intel Simulator and arm64
iPhone against unchanged sources. The normal Simulator update and rendered
installed-resource scene also pass, but that scene does not play original local
radio. Actual audible playback, retune/interruption behavior and hardware audio
acceptance remain open; SDK/build and PCM tests do not replace those checks.
