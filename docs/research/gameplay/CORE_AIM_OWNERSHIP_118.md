# Aim ownership at movement-task handoffs

Core118 retires an active gun-aim latch when a successfully admitted swimming,
parachute or climbing task takes ownership. The Renderer clears its aim state
and notifies the input/HUD owner synchronously, before another internal fixed
step can return to foot movement. Rejected transitions do not cancel aim.

The input owner reconciles against the same task predicate before hardware
polling and after outer movement slices. This is a defensive boundary; outer
slices alone cannot observe every internal transition. The camera independently
uses the predicate for both shoulder aim and scope selection, so an already
changed task cannot render through stale aim before the input owner polls.
Scope, FOV and follow interpolation retain the existing camera equations.

Eligible jetpack gun aim remains available. An actually flying weapon without
the existing `arm` capability loses aim; merely wearing a grounded pack does
not. The real flight task cancels an incompatible latch before its next step,
including a takeoff and touchdown within one outer call. No full control reset, synthetic
button release, movement constant, camera projection or response curve was
introduced. After task cancellation, native touch aim needs a new tap and a held
controller aim needs an actual release and press. Existing keyboard context
masking may produce its established fresh edge on return to foot. Neutral hardware
still preserves an ordinary touch toggle outside a canceled task.

## Evidence

In frozen Core117, new aim requests were rejected while swimming/parachuting,
but an existing latch was only cleared for climbing. The camera separately
consumed raw aim even though combat eligibility correctly blocked firing.
An unchanged held controller trigger produces no new hardware edge; neutral
hardware intentionally leaves a touch toggle alone. Keyboard context mapping
already suppresses aim in water/parachute and is a negative control.

A private bounded execution of the actual archived browser task and camera
methods clears camera aim/scope in active swimming/parachute states. This
establishes the in-task camera discrepancy. The browser can re-read raw held
input after returning to foot; native persistent cancellation/rearming is an
explicit input-ownership policy, not a claim of identical post-task input.
No retail runtime or physical-controller behavior was measured.

The archived effective-weapon selector also substitutes unarmed only when
actually flying with a weapon lacking `flags.arm`. A private actual-selector,
metadata and camera-eligibility witness retains compatible22 and rejects23/34
in flight while preserving all three on the ground. This supports the narrow
arm-capability boundary rather than a blanket jetpack aiming veto.

## Focused regression

```sh
python3 tests/combat/smoke_native_aim_ownership.py
python3 tests/combat/smoke_native_aim_ownership.py --baseline ../ZGTA-SA-core-117 --expect-historical-latch
python3 tests/combat/smoke_native_aim_ownership.py --baseline ../ZGTA-SA-core-117 --expect-historical-flight-aim
python3 tests/ui/smoke_native_camera_motion.py
```

The new asset-free gate extracts the production task-entry blocks, climb
admission, GVC callback/toggle/setter/poll/movement loop, shared predicates and
camera call. It runs the actual swim/flight controllers and camera, plus the
literal climb data declarations and initializer used by admission. This aim
harness does not call climb stepping or probe methods; the separate real
climb/movement gates retain that coverage. The unused stepping expression
exhausted an ARM CI compiler constraint budget even with a larger expression
timeout, so it is excluded from this focused carrier instead of replacing it.
It uses independently authored metadata. UI, unavailable geometry and unused clip
durations are explicit test boundaries. It covers 15/30/60/120Hz, scope and
shoulder aim, shore return, genuine rearming, rejected transitions, eligible
jetpack, direct render protection and accepted entry/exit inside one outer move.
The historical mode verifies the previous source keeps all three stale states.
The focused final run passes 4,851 checks; both historical modes reject the
old source with their separate diagnosed latch. The existing camera/motor,
bindings and controller-owner gates pass 4,118, 3,836 and 89 checks respectively.

The existing camera/motor gate retains its assertions and now extracts the
actual aim predicate and local camera-input expression as dependencies. Its
owner-local physics library/metadata requirements are unchanged. Host checks
are separate from full SDK builds and actual phone/Simulator acceptance.
