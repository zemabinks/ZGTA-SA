# Native vehicle exit placement — Core99

The driver now uses a clearance search before releasing a vehicle. A fixed
side offset or a captured animation root alone could put the actor inside a
wall, a tilted hull or an unloaded collision cell. The timed boarding queue,
local body parking, crash/wreck/water damage owners and existing exit packet
remain in use.

## Behavior

- Search the preferred side, eligible upper/lower routes for tilted vehicles,
  the other side, then front/rear routes. Retry with the original narrower
  capsule clearance and preserve the source's above-door/airborne fallbacks.
- Use original imported spheres/boxes, full model bounds, model origin and
  current physical quaternion. Empty collision geometry uses the source's
  dimension/wheel-based fallback. These data stay owner-local.
- Query ground and door reach with the original world collision mask. Check
  the actual native foot capsule against the shared Rapier world, excluding
  the owned rigid body and respecting promoted neighboring vehicles.
- Reconcile a completed door animation's facing with the selected feet and
  immediately reset the native foot motor at that same point. Missing rider
  metadata still allows a geometry-based exit for supported vehicles.
- Missing collision cells defer placement. The capsule's four horizontal
  corners are covered as well as the ground/reach rays. Keep the vehicle,
  controls, health prediction and exit packet unchanged until placement is
  available; request collision coverage through the normal world query path.
- Retry on the display loop. Cancel stale callbacks after a vehicle lifecycle
  change or controller/vehicle replacement. A completed wreck takes priority
  if the world changes while an ordinary exit is waiting. Apply damage and
  publish the final feet/parked snapshots only after the exit succeeds.

## Evidence and acceptance

`smoke_native_exit_placement.py` executes the actual archived browser planner
in an offline VM, then compares the independently written native search. The
controlled matrix has 13,568 cases across all 212 imported models, eight poses,
eight ground/obstruction policies, with/without preferred/seat positions and
standing-aboard probes. It checks both chosen positions and query counts.
Unknown query responses must propagate instead of becoming empty space.

`smoke_native_exit_runtime.py` uses the actual native planner, Renderer exit,
GameVC completion and retry methods with real imported geometry, animations,
Rapier and foot motor. It covers floors/walls, ten vehicle models with/without
rider metadata, delayed normal/crash/wreck/water exits, stale owners, a widened
capsule crossing a missing cell, delayed wreck escalation and completed exit
facing. Cell residency and outer UI/network owners are controlled test inputs;
the full rendered scene and live transport are separate acceptance boundaries.

Final acceptance:109/109 frozen regression gates pass, sources unchanged;
Release99 builds for Simulator and generic unsigned iPhone both pass. A
dedicated iPhone12Pro Simulator UIKit test joins as a guest, enters a seeded
QA taxi, exits and walks another5.18m. The real server records69 driving
samples and exactly one exit packet, with health100 preserved. The full
Simulator display is visually inspected after walking. UIKit app-screenshot
attachments crop the landscape viewport; the full display capture is the
visual evidence. These are local/native results, not retail comparisons.

## Remaining differences

This establishes bounded browser compatibility and native transition behavior,
not retail San Andreas timing or 1:1 feel. The running owner iPhone reference is
detected, but screen/automation access still awaits the owner's OS settings.

The browser planner itself retains a last-resort centre/ground fallback when
all tested capsule placements are blocked; this does not prove a collision-free
exit from every sealed space. Full passenger exits, jacking, moving jump-out,
rollover crawl animation, aircraft bail-out and unsupported/native-fallback
vehicle paths remain separate work. Original retail side-by-side, physical
controls, rendered door alignment and multiplayer peer-scene acceptance remain
open. No original scripts, collision rows or captured media are published.
