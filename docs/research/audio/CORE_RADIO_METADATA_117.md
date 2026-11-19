# Vehicle radio metadata and tuning ownership

The native source loaded its programme and audio index independently. Each
successful response called `enter(model:)` again. A late index could therefore
replace a station just chosen by the player with the vehicle default, turn a
deliberately disabled radio back on, or discard a supplied followed station.
This was a native asynchronous ownership defect; it does not establish a
retail programme-scheduling rule.

Metadata now resolves against the current vehicle entry and its current
station choice. A real new entry clears that choice and uses the existing
default/follow/remembered policy. Late classification still enforces off-only
and emergency vehicle rules. User choices made before the programme arrives
remain eligible only where that classification permits them. Exiting prevents
later source metadata from starting vehicle playback.

The normal 0.7-second tuning delay has a UUID owner. Metadata can update its
resources without skipping the pending delay. Supersession, departure or a
new entry retires that owner; even an already-dequeued old closure cannot
retune its replacement. A current completion tunes once. Existing station
rings, sample clocks and audio decoder behavior are unchanged.

`python3 tests/audio/smoke_native_radio_metadata.py` runs the actual extracted metadata
callbacks, selection, cycle and dial closures, with the actual programme
parser. Resource delivery, audio sinks and queued dispatch are explicit test
boundaries. Its focused run passes44 checks/15 cases. Optional
`--historical-root /path/to/Core116` requires the old source to compile and
fail the specific late-index selection assertion. Neither original audio nor
an audio device, OS socket or player engine is used.

The retained local raw-resource/lease/PCM suite separately passes32,177 checks
with mathematical audio fixtures. The updated radio source compiles and links
for arm64 iPhone, arm64 Simulator and x86_64 Simulator. Those checks do not
establish complete on-device station coverage, acoustic output, original
retail tuning delay, or a live network-propagated passenger radio policy.
An earlier fixture marker/parenthesis failure is retained separately from
these successful runs. Full App builds and normal runtime acceptance remain
separate gates.
