# Native radio

`prepare_native_radio.js` extracts the public client's actual sample counts,
song intro/middle/outro ranges, DJ/weather talk, adverts, station idents, WCTR
show groups, regional weather cycles and model radio defaults. Its output is
ignored `local-only/site/game/native/radio.program.json`; recordings are not
included. `NativeRadioProgram` translates the original deterministic station-day
program and shared sample clock. Joining a station seeks into its current piece.

The public original radio index returned 404 during the archive. Public program
metadata does not contain the music. To enable original stations with the
owner's existing files, register a local game folder:

```sh
node prepare_native_radio.js
node native_radio_server.js /absolute/path/to/owner/game
```

The reader locates `audio/config/strmpaks.dat`, `audio/config/traklkup.dat` and
`audio/streams/*`, preserving original global track IDs, 8068-byte stream headers
and absolute-offset XOR decoding. Registration copies no music. The local server
decodes each requested Vorbis track to 32 kHz float WAV on demand with the
project-local soundfile dependency; AVAudioEngine then schedules PCM pieces
without a WebView. All owner paths, stream data and decoded audio remain under
ignored local-only. Native playback keeps a 256 MiB device cache. The native
audio session's interruption/background lifecycle stops playback; returning to
the game rejoins the station's current shared time.
The Mac's generated WAV cache retains at most 2 GiB of recently requested audio
(a single larger current track is retained). Original owner streams are never
changed or deleted.
Conversion streams encrypted input in bounded chunks and runs at most two
decoder jobs concurrently; simultaneous clients share pending conversions.

Station overrides still work in `local-only/site/game/radio/custom/` as
`CH.mp3`, `CO.m4a`, etc. Other MP3/M4A/AAC/WAV filenames in that folder form the
User Track Player's shuffled playlist. Those files are also local only.

`native_radio_server.create().handle(req,res,pathname)` handles the native index
and `/game/radio/native/track/<id>.wav` routes after the host's existing access
checks. It supports GET, HEAD and byte ranges. Native calls `enter(model:)` to
apply original vehicle station/type rules and `synchronize(milliseconds:)` to
anchor station time to the server. The existing `resume()` API remains usable.

Validation:

```sh
zsh smoke_native_radio.sh
node smoke_radio_streams.js
zsh smoke_native_radio_pcm.sh
```

The scheduler comparison invokes the actual archived closure for 48 station-days
and compares all 101,312 program pieces, 384 sample seeks/day transitions and
232 vehicle defaults exactly. The owner reader is compared with original mH/mK
against synthetic pack/config files, including invalid records and unaligned
XOR byte ranges. A generated Vorbis fixture exercises native PCM conversion,
concurrent caching and HTTP range handling. Offline AVAudioEngine checks cover
sample-contiguous piece boundaries, stereo channels, mono duplication and EOF
silence. These checks verify capability with synthetic audio; original full
station recordings have not been available for end-to-end listening tests.
