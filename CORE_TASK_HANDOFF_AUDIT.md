# Core86 movement task handoffs

This pass repairs native update ownership and observable motion. It does not
establish original GTA San Andreas runtime parity. The original-game evidence
and outstanding runtime comparisons remain in `CORE_RETAIL_REFERENCE.md`.

## Water exit advances animation once

The fixed character callback tries swimming, then personal flight, then foot
motion. Previously `swimmingMotion` advanced the real `NativeFootAnimation`
before checking whether the swim controller had returned a movement result.
On water loss, negative depth, shallow grounded exit or completed haul, that
result is nil and the same tick proceeds to foot/flight. The animation controller
therefore consumed the tick twice.

The retained pre-fix probe reproduced all four paths using the current Renderer
methods and the owner's real 1,871-clip animation library. Each exit differed
from a single-update reference by 0.06666666666666665 in the outgoing blend
weight. The corrected paths match the single-update reference exactly. Stamina,
splash handling and the swim controller's physical exit conditions are retained;
only a successful swim task advances swimming animation.

The archived browser main19737 wrapper places its animation update inside the
successful `td.step` result branch (bounded retained wrapper evidence around
offset1,742,110). That corroborates the scheduling correction, but the native
reproduction independently establishes the duplicate update. Original animation
track identity alone does not prove retail transition timing.

## Available speed and committed momentum

`NativeCharacterController.stepVelocity` remains the last committed fixed-tick
velocity in Rapier axes and world units per second. No-tick display frames must
retain it: clearing it on every display update recreates the high-refresh alias
documented in `CORE_FIXED_STEP_VELOCITY_AUDIT.md`.

New read-only `movementAvailable` and `currentVelocity` distinguish that physical
handoff record from observable current motion. Missing collision geometry,
inactive ownership, invalid clocks and suspension expose zero current velocity.
They retain committed velocity and airborne rising for subsequent physical
handoffs. Reset/ownership changes start unavailable with zero committed velocity;
a valid geometry-ready update becomes available even before its first fixed
tick. Normal input cancellation does not erase momentum or availability.

Renderer camera and wire sampling consume `currentVelocity`. Task handoffs keep
using the committed record. This introduces no velocity averaging, new force,
unit/sign change or alternate display interpolation.

## New jetpack supersedes a landed canopy

The landed parachute presentation tail lasts up to2.17 seconds in the existing
controller. Starting a jetpack during that tail previously set `flying=true`
while leaving state10 dominant. The real flight presentation consequently
produced a landed canopy and no jetpack.

`takeOff` now discards obsolete parachute phase bookkeeping while preserving
equipment, current pilot controls, requested heading and supplied velocity.
Tests start new flight at three points within the landed tail; its next120 ticks
exactly match a fresh jetpack with the same state and inputs, including yaw wrap.
The real animation presenter immediately selects the jetpack and drops the
obsolete canopy.

This stale-state behavior also exists in archived54205. The correction is an
explicit native task-ownership invariant, not a claim of browser equivalence or
measured retail behavior. Previously covered ordinary flight behavior still
matches the archived reference across16,800 frames.

## Reproduce

```sh
python3 smoke_native_task_handoffs.py
python3 smoke_native_fixed_velocity.py
python3 smoke_native_heading_transitions.py
python3 smoke_native_climb_runtime.py
python3 smoke_native_controls.py
python3 smoke_native_personal_flight.py
python3 smoke_native_swim_sprint.py
python3 smoke_native_swim_animation.py
```

The new runner extracts the actual current Renderer task methods, links the real
character motor and accepted native Rapier library, and loads the owner's local
animation library. Water planes and pre-flight walking intent are controlled
fixtures. It checks four exit modes, observable/committed velocity boundaries,
water→foot→jetpack ownership across30/60/120Hz and uneven display timing, and
landed-canopy→jetpack transitions. It compares fixed-tick roots, phases, facing,
clip choices, times and weights. It does not replace production physics or
animation methods with duplicate test implementations.

Results recorded for this pass:

- Task handoffs:16,049 checks, zero failures, including swim/flight takeover
  clearing obsolete ordinary-foot fall history.
- Existing fixed velocity:69,333 checks across16 native motor/animation cases.
- Heading transitions:3,976 checks; prior180° snap remains corrected to0°.
- Climb runtime:8,369 checks,1,504 display frames,1,308 native physics ticks.
- Controls/cadence:14,576 checks across15–144Hz, suspension, controller rearm
  and shortest-angle ownership handoff.
- Personal flight:16,800 archived-reference frames,152,166 comparisons;
  maximum numeric difference1.07e-14.
- Sprint/swimming:15,300 reference frames,88,061 comparisons;
  maximum numeric difference4.45e-16.
- Swimming presentation:1,600 frames,12,762 comparisons across all seven states,
  haul and exit fade.

Private baseline/final results, generated replay source and scoped source hashes
remain under `local-only/research/task-handoffs/`. `--record-baseline` records the
currently selected source without enforcing repaired invariants; it does not
restore old code. The retained original pre-fix report records15 failures across
30 boundary checks. No original assets, browser excerpts or executable bytes are
included in the source release. Native libraries were not modified or rebuilt.

## Remaining boundaries

- No original retail executable or physical-device comparison was performed.
- Controlled water and intent fixtures do not establish every world-water edge,
  carrier, collision seam or input-device behavior.
- Static climbing retains its explicit moving-handhold limitation.
- This pass does not change browser/native display interpolation differences,
  swimming haul geometry, health authority or the general frame-clock policy.
- Menu/background lifecycle and camera checks are separate integration gates;
  the tests here establish controller/task behavior rather than UIKit capture.
