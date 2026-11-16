# Bike crash, rollover and forced foot handoff

Core94 adds the missing motorcycle/bicycle rider-ejection path. The existing
bike force solver and chassis damage ran without forwarding a crash to the
rider. Native now observes each owned chassis contact at the original
impulse/50 boundary, weights the original directional impact and keeps the
strongest queued ejection with its preceding physical velocity. Taking that
event consumes it once. Unoccupied bikes and ordinary cars do not eject a local
bike rider; replacement and relocation discard obsolete events.

The rollover path requires a preceding chassis contact. An inverted bike can
throw immediately; a slowly fallen bike must remain down for more than500ms.
A bike in free flight does not become a ground rollover merely because it is
banked. The original Sanchez468 impact modifier is retained. These rules use
fixed physical ticks and keep their own contact/timer owner.

After the complete native vehicle update publishes its final pose, the game
controller performs the forced exit. Boarding/door-exit tasks keep their current
ownership. A forced exit uses the original adjacent point derived from the
entry animation's terminal root when that metadata is available. It parks the
actual physical bike, retains its momentum and publishes the existing exit
packet. It then activates the foot motor, releases vehicle controls and audio,
plays the directional knock or fatal pose, and reports the crash amount once through
the shared armour/health impact owner. It does not play a new timed door-exit queue.

## Verification

- Actual archived52431 impact weighting plus62540 rollover expressions:
  4,200 impact cases,3,840 rollover frames,24,255 checks, maximum force error0.
- Actual native chassis/physics lifecycle gate:112 checks, including occupied
  motorcycle522 and bicycle481 contacts, car420 and unoccupied controls,
  preceding impact velocity, one-shot consumption and teleport cleanup.
- Extracted current Renderer and Game controller exit methods with real native
  vehicle/foot/parked physics and local original clips:288 checks. Outer UI and
  network owners are explicit spies. Foot coordinates, directional down tags,
  damage count, parked momentum and duplicate exit suppression are checked.
- Original rider playback/adjacent-point geometry, the whole frozen core suite
  and both Apple builds have separate final acceptance records.

## Remaining limits

The independent native health interface uses integer health. Ejection damage
therefore rounds up at that existing boundary. The finalCore97 health owner
applies armour before health and deduplicates the acknowledged impact; the archived actor can retain
fractional health. Precise retail damage/feel is not established by these tests.

The original general ground/door-clearance placement planner is still absent.
Missing rider metadata falls back to captured rider feet or the current vehicle
pose. The original adjacent animation point is not a claim that every blocked,
inverted or missing-geometry exit is already identical. Passenger ejection and
full vehicle-to-pedestrian ramming/blade contacts remain separate gaps.

Rendered rider alignment, real browser/native scene observation, touch or
controller hardware, retail runtime comparison and iPhone performance remain
unverified. Assets and observations stay owner-local. No1:1 accuracy is claimed.
