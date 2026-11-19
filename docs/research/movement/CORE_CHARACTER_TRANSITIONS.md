# Native character task boundaries

This audit covers the native walking coordinator and its Rapier query adapter.
It does not establish equality with a retail GTA SA executable. The synthetic
native worlds below establish lifecycle and frame-cadence invariants. The
existing archived public-client replay is a separate, secondary compatibility
check for uninterrupted walking math.

## Reproduced defects

* A falling character entering `Motion.heldFeet` retained its old downward
  velocity. Releasing the animation root resumed that old fall. The measured
  pre-fix inherited velocity was -6.6364414986633955 m/s.
* A root-owned task could publish the previous walking tick's vehicle press.
  Missing collision geometry likewise left the prior press in public state.
* `setActive` cleared visible flags but retained the prior slope normal and
  barrier. A reset followed by `stand()` could still be barred by a slope at
  the old location, and the old normal altered easing at the next step.
* The coordinator silently capped each call at 100 ms. Two seconds of 5 Hz
  movement became 60 ticks / 2 m instead of 120 ticks / 4 m; 8 Hz became 96
  ticks / 3.2 m. The outer app clock usually subdivides input already, but
  direct coordinator callers still had inconsistent behavior.
* A long suspension was applied as one stale 100 ms movement/jump command.
  Invalid callback roots or vertical inputs could poison persistent pose.

## Ownership rules

`reset(feet:active:grounded:)` and activation/deactivation begin a new walking
task. They clear pending fractional input, surface/contact/exclusion histories,
vertical velocity and step easing. Other vehicle collider registrations remain
owned by the shared world and are preserved.

A finite `Motion.heldFeet` owns position. Entering it resets walking motion
once, publishes zero rising velocity and no grounded/press result, then keeps
the walker capsule at the externally supplied root. The first ordinary step
starts from that root. The renderer does not need to call `motor.setActive`
on every climb tick.

Missing collision cells pause this coordinator. Position and physical vertical
momentum are retained, input debt and transient contact events are dropped,
and no catch-up is attempted when cells return. A clock discontinuity follows
the same pause rule. This differs deliberately from a new walking task.

Positive elapsed samples through 0.5 s retain all time and are integrated at
1/60 s, at most 30 ticks per call. Greater or invalid samples are discontinuities.
The 0.5 s boundary matches `NativeGameFrameClock`; it is an application pause
policy, not a claimed retail timing constant.

## Verification

```sh
python3 tests/movement/smoke_native_character_transitions.py
zsh native-physics/test_character.sh
```

The new gate compiles an immutable source snapshot against the existing host
library. It writes only under `local-only/native-physics/tests/character-transitions`.
It checks native-world root/release, vehicle press, teleport, deactivation,
carrying exclusions, cell loss/resume, malformed motion, and fractional input
handoffs. Per-tick state is compared across jump, ceiling, wall, stairs, ordinary
and slippery slopes, falling, root-owned and swim-override fixtures at
5/8/15/30/60/120/144 Hz plus uneven cadence. No game assets are required.

Core80 results: 39,068 checks passed, including 12,960 frame-by-frame native
comparisons with zero position, rising-velocity, easing or contact-state
differences between cadences. Running the same gate against frozen Core79
source reproduced 35 failures. Its reset-from-slope easing differed from a
fresh walking task by 0.01999998807907109 m; Core80's difference was zero.

To reproduce the defects with a preserved older source tree while keeping
all generated files in the current tree:

```sh
CHARACTER_SOURCE_ROOT=/path/to/older/source \
CHARACTER_REPORT_NAME=pre-fix.json \
python3 tests/movement/smoke_native_character_transitions.py
```

`test_character.sh` separately executes the actual archived browser motor and
compares 2,100 native motor/query/core frames. Its raw archive and generated
measurements stay local. Passing that test demonstrates that the lifecycle
changes leave uninterrupted reference movement intact; it is not retail proof.

## Boundaries and unresolved work

Gravity, jump impulse, slope limits, KCC configuration and collider dimensions
are unchanged. In particular, this motor has no collision-stance parameter:
visual crouching does not currently resize its walker/probe. Lower-tunnel
crouching needs verified stance geometry and its own transition/clearance
implementation. The audit does not substitute guessed retail dimensions.

The adapter, Rust/C ABI, headers and frozen physics libraries are unchanged.
App build, device performance and visible gameplay acceptance remain separate.
