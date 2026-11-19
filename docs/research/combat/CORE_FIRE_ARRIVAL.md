# Animation-driven fire and receive-time credit

This is an independent multiplayer transport correction. It does not change
the native animation, weapon skill, accuracy, damage, reload or sustained fire
interval, and does not establish original retail gameplay parity.

## Reproduction and cause

Core86 live testing fired a native Colt 45 while the server also reported that
its fire interval had not elapsed. The local visual event and authoritative
inventory result could disagree even with normal held input.

The receive-time token bucket started a fresh player with one token although
its maximum catch-up allowance was larger. A display frame can deliver multiple
simulation events together. Even evenly timed single shots can arrive slightly
closer together than their emission interval. Starting the bucket partly empty
turned that first timing variation into an inventory rejection.

The real native `NativeFootAnimation`/`NativeGunAnimation` code and owner-local
CLP data reproduced this across stationary standing/crouched profiles for
weapons 22/26/28/30/37/41/42. Grouping those events at 15/30/60/120/144 Hz and adding
bounded 0–20 ms arrival jitter produced 568 rejected events in 106 of 140 cases.
The total was 69,060 native emissions across all scenarios. Large synthetic
magazines isolate cadence; this is not a utility-shop or reload test.

## Correction and bounds

Fresh traffic starts with the existing full ordinary two-event allowance.
Continuous stream traffic receives five tokens: four possible grouped native
events plus one 20 ms interval of arrival variation. The old four-token stream
ceiling still rejected valid 15 Hz traffic with 20 ms jitter after startup; filling
the old bucket alone did not solve that case.

This deliberately increases the independent server's maximum stream transport
burst from four to five. It preserves the same canonical token refill interval
and long-term rate. It does not accelerate the native animation. A second peer
nonce, a weapon change, invalid timestamp or rejected request cannot refill the
bucket. A persisted last-shot timestamp keeps its elapsed-time cooldown across
a server restart; it does not receive a fresh free burst.

## Verification

- `python3 tests/combat/smoke_native_fire_arrival.py`: 140 cases and 69,060 actual native
  animation emissions accepted; historical control reproduces 568 rejections.
  It compiles frozen native helpers against the real local CLP and records
  source/data digests and unchanged-source status privately.
- `node tests/combat/smoke_weapon_transport.js`: 50,080 synthetic checks, 50 grouped cases
  and 32,310 events. Tests include burst ceilings, sustained one-millisecond
  pressure, replay, weapon change, reconnect scope, restart cooldown and
  backward clocks. Its historical control reproduces 260 rejections.
- Existing inventory purchase/reload tests now explicitly consume and exhaust
  the two-event startup allowance. The ACK and actual-server cadence tests
  retain a saved-shot scenario for rejection/replay and add a fresh actual
  backend two-event burst check. Rejected sequences still cannot become
  billable retroactively through the ACK protocol.

These results cover the stated synthetic arrival envelope. Real network loss,
larger jitter, TCP head-of-line stalls, latency over the internet, very low
frame rates and physical-device behavior are not established by this test.
The existing native animation catch-up bounds remain unchanged. No original
game executable or original server implementation was run for this correction.

The native App source is identical to the Core86 Release build. This batch
changes independent server credit, regression tools and documentation only;
it does not claim a newly built or physically tested iPhone binary.
