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

For the normal local site, this existing command writes its ignored owner registration:

```sh
node native_radio_server.js /absolute/path/to/owned/game
```

It records the owner directory and copies no music. The server lazily converts requested tracks to 32 kHz float WAV using `prepare_native_radio_audio.py` and the project-local `local-only/toolchains/python-audio` dependency. `ZGTA_PYTHON=/usr/bin/python3` selects that interpreter explicitly on the tested Mac.

For a disposable QA site, put the selected programme at that site's `game/native/radio.program.json`. Give its `game/radio/owner.json` this structure:

```json
{"directory":"/absolute/path/to/owned/game"}
```

The QA host must instantiate the radio helper with the QA paths:

```js
const radio = require('./native_radio_server').create({
  configuration: '/absolute/path/to/qa-site/game/radio/owner.json',
  cache: '/absolute/path/to/qa-site/game/radio/native-cache',
  python: '/usr/bin/python3'
});
```

The default helper paths refer to the server source root's local site. Use the explicit paths above when running from the normal source root, or use a separate copied server source root whose `local-only/site` points to the QA overlay. Existing access checks still precede `radio.handle(req, res, pathname)`.

Conversion uses at most two concurrent decoder jobs. The Mac cache retains 2 GiB of recent generated audio, and the native device cache retains 256 MiB; a single larger current file can remain. Complete predecoding is unnecessary. The tested owner radio sources total about977MB compressed; all decoded float PCM would occupy about15GB.

## Verification and limits

`node smoke_radio_import_bounds.js` is self-contained and passes under Node22 without an archive. It checks both size conventions, unaligned XOR ranges, exact EOF, metadata, preserved compatibility input and overlapping-range rejection using synthetic format pages. It does not claim those pages are listening-test audio. Existing synthetic Vorbis, conversion/cache/HTTP range and archived scheduler regressions also pass.

The local original-file gate inspected all 1731 tracks across 13 owner packs, finding stereo 32 kHz streams and 613 affected sizes. It decoded 15 actual recordings, compared 13 legacy shortened frame counts, checked 45 native PCM windows and 752000 exact channel samples, and rendered a real transition through AVAudioEngine's offline mode. Full-recording programme generation covered all 12 internal station programmes. These checks used no microphone or speaker output.

The optimized79 Simulator subsequently entered a car, selected Bounce FM, switched to SF-UR and exited on the isolated loopback world. Three requested PCM files appeared in both its Mac and native app caches. This verifies the live UI/download flow alongside the separate offline sample proof; physical-device listening and interruptions remain unverified. This evidence does not certify1:1 retail radio scheduling.
