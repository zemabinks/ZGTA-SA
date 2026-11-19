# Browser owner radio

`native_radio_server.js` serves compressed owner radio to the browser alongside
its existing native WAV routes. It uses the same private owner registration;
no recordings, lookup tables or owner paths are included in source responses.

After the host's existing Host, Origin and join checks, dispatch:

```js
if (radio.matches(pathname)) {
  void radio.handle(req, res, pathname);
  return;
}
```

The helper does not authenticate requests. The separate token-authenticated
development radio process retains its own native-only route allowlist.

`GET /game/radio/index` returns only
`{stations: [[[id, seconds], ...], ...], adverts: [[id, seconds], ...]}`.
Numeric lookup IDs, station ordering and empty slots remain intact. Durations
come from complete Ogg end granules divided by the recording's sample rate;
they must be positive and finite. These are recording lengths, not a change to
the archived programme counts or proof of retail on-air scheduling.

`GET /game/radio/track/<id>` returns the complete decrypted compressed Ogg
payload as `audio/ogg`. It supports a single closed, open-ended or suffix byte
range, with `206` and exact `Content-Range`. `HEAD` returns corresponding
headers without opening a body stream. Unsafe, malformed, multiple or
unsatisfiable ranges receive `416`; missing or malformed IDs receive `404`;
other methods receive `405`. An unavailable index or invalid metadata receives
a sanitized `503`. Unknown routes remain the host's responsibility.

The browser path never converts to PCM. Its body pipeline reads at most64KiB
per chunk, applies XOR using the absolute bank offset, respects response
backpressure and closes its file descriptor on cancellation. Source changes
during a response abort that response instead of appending an error body.

Metadata uses the existing64MiB bound per compressed record. A first index
inspects the available recordings and yields between records so gameplay
timers can run. Subsequent unchanged indices reuse the parsed metadata.
Registration, lookup-table and bank identity/size/timestamps invalidate the
cache; bank replacement is detected even when its size and mtime are retained.
An explicitly selected registration never falls back to another owner. Once a
preferred registration has been selected, deleting it also cannot reactivate
an older legacy registration in the running helper.

Run `node smoke_browser_radio.js` for126 authored checks of the actual handler,
including exact full/range payload identity, suffix and unaligned ranges,
metadata validation/caching, event-loop yielding, backpressure/cancellation,
owner changes, sanitized failures, unchanged source files and native WAV
conversion/cache/range behavior. Its format carriers are not playable audio;
the test uses no original recordings, network listener or audio device.

Run `node smoke_browser_radio_http.js` for41 checks through a temporary real
`serve_local.js` listener. It exercises the normal remote join cookie, Host and
Origin checks, native/browser indices, full and ranged compressed delivery,
HEAD, malformed IDs/methods, source immutability and sanitized source failure.
It uses authored format carriers and stops its own listener afterward.

Register your own local source with
`node native_radio_server.js /absolute/owner/game/directory`, then run the
normal self-host. Registration remains private under `local-only` and refuses
to replace an existing owner. A first index reads compressed metadata; later
unchanged requests reuse it. Browser playback must still be tested separately
from HTTP delivery. Neither passing these gates nor decoded samples establishes
audibility, original on-air scheduling or complete gameplay parity.
