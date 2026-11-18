# Fixed-tick weapon batches

The independent server now admits a bounded batch of fast gun events delivered
by one low-frame-rate display update. It retains the existing server-time
sustained fire interval and never accepts a client's claimed elapsed time.

The native controller advances animation/physics in fixed ticks, so several
legitimate markers can be sent together. The minigun profile is an ordinary
fast gun, rather than one of the profiles classified as a stream. It therefore
kept only two burst credits after the earlier stream fix. A source replay with
the actual archived gun state machine and existing clip duration reproduced
valid-event rejection at both 15 and 30 display updates per second. The native
animation-to-ammunition boundary already preserves same-clock events; adding
another local fire timer would address the wrong owner.

For ordinary guns, transport capacity is now the number of intervals fitting
one 15 Hz frame, rounded up, plus one phase/jitter credit, clamped to two through
five credits. Existing streams retain five credits. Slower ordinary guns retain
two. Refill still uses the original interval and server time; repeated same-time
requests, switches, reconnect scopes and restarts cannot manufacture sustained
rate credit. This is an independent transport policy, not a retail gun constant.

Run the asset-free regression:

```sh
node smoke_weapon_frame_batches.js
node smoke_weapon_transport.js
```

The first runs 28 independently authored rate/frame combinations at
15/30/60/120 Hz, plus burst, sustained-rate, replay, clock, switch, ammunition,
reload, health and passive guards. It needs no game assets, socket or service.
Its optional `--historical-module /absolute/path/to/weapon_inventory.js` mode
reports the expected failure of the older policy separately. The existing
transport regression preserves its original historical negative control.

Private before/after replay also checks actual profile timing, but its original
scripts, clip metadata and generated event traces remain local. It is not a
new physical-device, full-game or retail-accuracy acceptance result. Long stalls
beyond the admitted batch window remain bounded and may require authoritative
ammunition reconciliation. No iOS source, animation timing, damage rule, weapon
model or physical force changes in this correction.
