# Native compressed radio foundation

This component decodes bounded owner-supplied PC San Andreas radio records to
finite stereo float PCM at32,000Hz. It does not play audio, access a network,
discover an installation, authenticate original resources, or activate an App
installation. Raw-resource leases, prepared-package schema and vehicle playback
remain separate integration work.

The independently authored Swift `NativeRadioArchive` reads the two lookup tables
and explicit pack lengths. It preserves original numeric track IDs, exact
header-inclusive/payload-only ranges, missing/excluded classifications and pack
identities. Its `Substream` duplicates a readable regular FD and performs bounded
positional XOR reads without moving the caller FD's position. Neither component
contains any game recording or original game's implementation.

## C API and ownership

Include `include/zgtasa_native_audio.h` or import the Clang module
`CZGTANativeAudio` from `include/module.modulemap`.

1. `zgta_radio_create(fd, record_offset, record_bytes, &handle)` duplicates the
   readable regular FD. The record range includes its8,068-byte header. The
   caller still owns its FD and may close it after successful creation.
2. On one serial worker, `zgta_radio_prepare(handle, &info)` validates the entire
   bounded Ogg record, then opens the reference decoder. No entire pack is read
   or copied. `info.frames` is the complete recording's decoded sample count.
3. `zgta_radio_read(handle, first_frame, frames, stereo, capacity_floats, &written)`
   reads an exact PCM window of at most8,000frames into interleaved stereo float.
   Mono is duplicated. EOF may return fewer frames; errors set `written=0` and the
   caller must discard any partially written output. Nonfinite samples fail.
4. `zgta_radio_cancel(handle)` is sticky and thread-safe. It may overlap the serial
   worker's prepare/read. Cancellation is checked between bounded I/O/decoder
   work; it cannot preempt an OS filesystem stall inside `pread`.
5. Join that worker **before** `zgta_radio_destroy(handle)`. Destroy/cancel may not
   race each other. Destroy closes the duplicated FD and releases all owned
   allocations. It never closes the caller FD.

All operations except cancel have one serial owner. `get_stats` is also a serial
owner call. No other-thread reads of decoder state are supported. The decoder
retains source device/inode/size/mtime/ctime identity and rejects changes. This is
not SHA authentication: the integration must supply an already verified,
generation-bound resource lease and cancel old handles when that lease changes.

The current station program's `plays` values must remain independent of complete
recording length. Existing browser-compatible sample counts differ from complete
end granules for613 owned tracks. Do not replace the program clock or its lengths
merely because the decoder can now return complete recordings. Request only the
piece's needed samples; playback policy owns any intentional padding/fade.

## Bounds and failures

- Record payload: at most64MiB; checked64-bit range arithmetic and signed OS offset
  bounds. Every source read is at most65,536bytes, using positional I/O.
- Ogg: CRC, version, header flags, serial, sequence, continuation/lacing, three
  Vorbis headers, sample rate/channels, granules and exact EOS/record-end checks.
  Chained streams and mixed/unsupported formats are rejected.
- At most100,000pages,200,000packets and1MiB per packet; comments/vendor/counts have
  additional bounds. Source duration is capped at24hours of32kHz PCM.
- At most8 live decoder handles. Xiph allocation requests, including this
  adapter's allocation headers, are limited to16MiB per decoder. Individual
  explicit stack allocations are at most256KiB, with2MiB requested per operation;
  each operation has an allocation-count and source-byte work budget.
- Unchanged upstream C may dereference a failed allocation. The compile-prefix
  allocator therefore escapes to the guarded C call on exhaustion rather than
  returning NULL into partial upstream state. Every persistent codec allocation
  is tracked and released after that abort; a poisoned handle is not reused.
- Reported heap statistics count requested blocks and adapter headers, not the
  system allocator's internal overhead. The bounded preflight scratch buffers
  (1MiB packet plus65,307B page) and compiler/static stack frames are separate.
  These are resource bounds, not iOS memory/performance measurements.

The callback uses **absolute pack position**, including record offset/header, for
XOR phase. Seeking must not restart that phase at zero. The Swift catalogue treats
three padding bytes after the byte-sized pack index as padding, not an integer
index; legitimate owner tables contain nonzero padding there.

## Reproducible Apple builds

The selected Xiph sources are already present. Build uses Xcode tools and Python
standard library, without downloading, autotools, an encoder library or CLI:

```sh
python3 native-audio/build.py --platform all
```

Libraries, link probes and source-stamp metadata go only beneath this checkout's
`local-only/native-audio`. A custom `--output` must also be beneath this checkout's
`local-only`. Linked output paths/artifacts and linked/changed vendor inputs are
rejected. The build verifies pinned per-file source hashes before and after
compilation; `zgta_radio_source_stamp()` must match the linked library's recorded
source stamp. No game data is consumed by the build.

Supported compile/link targets: macOS x86_64/arm64, iPhone arm64 (iOS15 minimum),
and Simulator arm64/x86_64. A successful compile/link does not execute an iOS or
Simulator decoder and does not establish playback, device timing or retail parity.
App project/library integration is intentionally absent at this layer.

## Upstream provenance and licenses

`vendor/provenance.json` lists every retained source/license file's exact bytes and
SHA-256. Sources were selected from the official archives after verifying the
published archive hashes:

- libogg1.3.6 `.tar.xz`: `5c8253428e181840cd20d41f3ca16557a9cc04bad4a3d04cce84808677fa1061`
- libvorbis1.3.7 `.tar.xz`: `b33cc4934322bcbf6efcbacf49e3ca01aadbea4114ec9589d1b1e9d20f72954b`

[Official release table](https://www.xiph.org/downloads/),
[Vorbis callback API](https://xiph.org/vorbis/doc/vorbisfile/ov_open_callbacks.html),
[PCM seeking](https://xiph.org/vorbis/doc/vorbisfile/ov_pcm_seek.html).

Upstream files are unchanged BSD3 source, including its release-provided CRC
lookup header. The build applies one exact, hash-pinned upstream compatibility
change to a private compiler input: the
[unsigned codebook-prefix shift fix](https://github.com/xiph/vorbis/commit/bb4047de4c05712bf1fd49b9584c360b8e4e0adf).
Its original/patched hashes and upstream commit are recorded in
`patches/vorbis-sharedbook-unsigned.json` and each archive's build receipt.
Strict UBSan found the signed shift during the authored normal decode test;
no sanitizer check is disabled. The release files in `vendor/` stay unchanged.
No configure/autotools/build artifact was imported. Apple's native
types branch requires no generated Ogg config header. Independent build flags,
allocation prefix and source-stamp metadata are ours and recorded separately.
The common upstream codec sources retain shared encoding routines unchanged;
`libvorbisenc`, encoder setup/books, command-line tools and examples are excluded.
Our public C ABI exposes decoding only. We do not claim that every shared encoder
routine is absent from a static archive.

Keep both complete upstream COPYING notices with redistributed source and the
App's third-party notices/materials. These licenses cover codec software, not
original GTA recordings. Our adapter/parser/build/test source is AGPL-3.0-only.

## Tests

```sh
python3 tests/audio/test_native_radio_audio.py --all-platforms --sanitize
```

For a repeat regression, `--library-root` and `--sanitized-library-root` may
reuse build outputs only after exact source-stamp, target, sanitizer-mode and
archive/link-probe digest checks. Reuse does not skip decoding assertions.

The portable suite contains only independently authored mathematical tone
fixtures, encoded once using soundfile0.13.1/libsndfile1.2.2 and retained as small
text fixtures. It needs no installed game or Python audio package. It checks real
C/Swift behavior, finite stereo/mono output and independent reference sample
windows, exact seeks/EOF, bad CRC/truncation/format/sequence/chaining, a malformed
setup that exceeds the allocator budget, source changes, cancellation, descriptor
ownership/leaks and limits, mixed table conventions/aliases and bad ranges,
source stamps, linked output rejection, and supported host sanitizers. Sanitizer
runs halt on errors; no Apple LeakSanitizer support is assumed.

Actual-owner recordings, lookup oracles, freshly hashed bounded input ranges and
representative libsndfile comparisons are private under `local-only`. They are
not portable fixtures and do not establish whole-owner decoding, iOS runtime,
audio hardware or completed offline radio. Never publish original recordings,
converted audio, archive data or archived original browser factories.
