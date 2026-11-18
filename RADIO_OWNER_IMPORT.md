# Owner radio import

The native radio player can use the owner's San Andreas PC audio files. Recordings, lookup tables, generated programmes and PCM caches stay under ignored `local-only/`; the source release contains no recordings.

The owner directory must contain `audio/config/StrmPaks.dat`, `audio/config/TrakLkup.dat` and the corresponding `audio/streams` files. Discovery accepts different filename casing and a surrounding game folder. The station packs, emergency radio and adverts use the existing native station scheduler and PCM player. Custom user music remains a separate playlist.

## Complete payloads and programme choices

The supplied PC lookup contains two size conventions: some records include their 8068-byte header and others describe only the audio payload. `radio_streams.js` now normalizes a payload-only record when the next valid record or file boundary proves the additional header span. It rejects an advertised range that crosses the next track. The previous reader cut 8068 bytes from affected recordings.

There are two explicit programme choices:

- **Browser compatibility:** `prepare_native_radio.js` preserves the archived sample counts and deterministic browser schedule.
- **Full recording:** `prepare_owner_radio.js` reads complete Ogg end granules and writes a separate sample-count variant. The existing native JSON loader accepts it without an App change. This establishes complete recording lengths; the original retail game's on-air cuts and scheduling policy remain unverified.

Prepare both locally, preserving the compatibility input:

```sh
node prepare_native_radio.js local-only/radio-import/radio.compatibility.program.json
node prepare_owner_radio.js \
  local-only/radio-import/radio.compatibility.program.json \
  /absolute/path/to/owned/game \
  local-only/radio-import/radio.full-recording.program.json
```

Serve the chosen file at `/game/native/radio.program.json`. The full-recording helper creates a new output exclusively: it refuses to replace existing files, including aliases of its compatibility input. Its metadata scan allows at most 64 MiB of compressed data per track. A partial or malformed stream fails instead of supplying an invented duration. Choosing the full variant changes the browser-derived sample clock; clients using the baked-in compatibility counts can therefore hear a different programme position.

## Registration and isolated QA

For the normal development host, register the owned game directory:

```sh
node native_radio_server.js /absolute/path/to/owned/game
```

This writes `local-only/native-radio-owner.json` and copies no music. Registration and the default `local-only/native-radio-cache` are outside the archived site, which can therefore remain a read-only alias. The command refuses existing registrations and linked output ancestors; to change an owner source, explicitly remove the old registration or choose a new private configuration filename. The helper still reads the older `local-only/site/game/radio/owner.json` when no new registration exists. An explicit or present new registration is authoritative: an invalid one does not borrow another source.

The host can lazily export requested tracks through the same bounded compressed-bank decoder used by native iOS, without installing Python audio packages. Link the small exporter against an already built, verified host library:

```sh
python3 build_radio_development_decoder.py \
  --library-root local-only/native-audio/targets \
  --output local-only/native-radio-tools
```

Set `ZGTA_RADIO_DECODER` to the absolute path of `local-only/native-radio-tools/radio-wav` when starting the development host, or pass the helper's `decoder` option. The link helper verifies the current source stamp and library hash and requires a new output directory. If no host library has been built yet, first run `python3 native-audio/build.py --platform host --output local-only/native-audio/targets`. The generated tool, libraries and PCM remain local. Export validates each complete bounded Ogg record before decoding, writes float WAV in small windows, refuses existing outputs and removes incomplete files on errors.

Without `ZGTA_RADIO_DECODER`/`decoder`, the older `prepare_native_radio_audio.py` path remains available. That path needs the project-local `local-only/toolchains/python-audio` dependency or an interpreter with SoundFile installed; a copied source checkout does not acquire those dependencies automatically. `ZGTA_PYTHON=/usr/bin/python3` selects its interpreter explicitly.

For a disposable QA host, keep its registration and cache in regular private directories. Its read-only site may continue to provide the existing `game/native/radio.program.json`. Register an explicit output:

```sh
node native_radio_server.js /absolute/path/to/owned/game \
  --configuration /absolute/path/to/qa-private/radio-owner.json
```

`serve_local.js` accepts `ZGTA_RADIO_CONFIGURATION=/absolute/path/to/qa-private/radio-owner.json`, `ZGTA_RADIO_CACHE=/absolute/path/to/qa-private/native-radio-cache` and `ZGTA_RADIO_DECODER=/absolute/path/to/qa-private/radio-wav`. A separate QA host can instantiate the helper with the same paths:

```js
const radio = require('./native_radio_server').create({
  configuration: '/absolute/path/to/qa-private/radio-owner.json',
  cache: '/absolute/path/to/qa-private/native-radio-cache',
  decoder: '/absolute/path/to/qa-private/radio-wav'
});
```

The default helper paths refer to the server source root's `local-only` directory. Custom user songs still come from its `site/game/radio/custom`, or an explicit `customDirectory` helper option. Existing access checks still precede `radio.handle(req, res, pathname)`; registration does not publish local filenames or recordings to GitHub.

This is a development streaming path. Native playback first checks the app's verified raw-resource receipt and reads compressed owner banks locally when present. A prepared visual-resource package alone does not import those raw radio banks. Installed-resource mode remains fail-closed for missing `/game/` files, so it will not silently request development radio from the Mac. Use the existing raw original-resource import for on-device original radio, or deliberately choose the app's development resource mode while using the configured development host. Invalid local banks continue to report a verification error instead of silently changing sources.

An isolated radio-only process is available with `node serve_development_radio.js --port <unused-port>`. It requires all four absolute private paths in `ZGTA_RADIO_CONFIGURATION`, `ZGTA_RADIO_CACHE`, `ZGTA_RADIO_DECODER` and `ZGTA_RADIO_TOKEN_FILE`. The token file must have owner-only permissions and contain a random 64-character hexadecimal token. This process binds only to 127.0.0.1 and accepts GET/HEAD for `/game/radio/native/index` and `/game/radio/native/track/<numeric-id>.wav`, including their normal revision query. Requests need `X-ZGTA-Radio-Token` and a loopback Host matching its port. It does not serve the site, custom songs, gameplay state, saves or resource installation. A LAN host must perform its existing authentication before forwarding these radio requests and add the helper token itself; keep that token out of client code and responses. Running this process does not change the app's installed-resource policy.

Conversion uses at most two concurrent decoder jobs. The Mac cache retains 2 GiB of recent generated audio, and the native device cache retains 256 MiB; a single larger current file can remain. Complete predecoding is unnecessary. The tested owner radio sources total about977MB compressed; all decoded float PCM would occupy about15GB.

## Verification and limits

`node smoke_radio_import_bounds.js` is self-contained and passes under Node22 without an archive. It checks both size conventions, unaligned XOR ranges, exact EOF, metadata, preserved compatibility input and overlapping-range rejection using synthetic format pages. It does not claim those pages are listening-test audio. Existing synthetic Vorbis, conversion/cache/HTTP range and archived scheduler regressions also pass.

`node smoke_radio_development.js` uses authored opaque pack bytes and no network listener. It checks private registration, read-only site aliases, explicit QA sources, legacy compatibility, source precedence, linked-path and overwrite refusal, CLI registration and sanitized index responses. These index tests do not decode audio or prove audible playback. The independent Core113 implementation and validation limits are summarized in `CORE_DEVELOPMENT_RADIO_113.md`.

`python3 test_radio_development_decoder.py --decoder /absolute/private/radio-wav --output local-only/new-decoder-test` exercises the actual exporter and development helper with independently authored mathematical Vorbis fixtures. It checks reference samples, WAV metadata, private exclusive outputs, malformed streams, linked outputs, native conversion without Python audio dependencies, deduplication and byte ranges. It needs the verified exporter above and opens no listener or audio device.

Original recordings and detailed owner-file/device evidence remain local. Development streaming does not establish installed offline audio, all-station playback, interruption handling or1:1 retail programme scheduling.
