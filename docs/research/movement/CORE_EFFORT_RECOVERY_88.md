# Core88 movement effort and recovering breath

These corrections follow the archived pedestrian's actual steering/status
boundaries. They repair native integration omissions; they do not establish
original retail stamina, lung-capacity or body-stat curves.

## Corrected ownership and ordering

The native coordinator had moved effort work into individual movement tasks.
Some early returns skipped source behavior, and swimming recovery ran after
its state transition instead of during steering.

- Exhausted underwater movement now prepares its effort budget before sprint
  control. The archived pedestrian restores a nonpositive budget to 0.1 in
  this mode; underwater effort itself has no cost. A drained foot budget no
  longer delays underwater input response until ordinary recovery catches up.
- A parachute recovers effort through the same source locomotion recovery
  function with ratio zero. This does not reset the shared sprint counter or
  cached sprint pace, which the archived parachute early return preserves.
- Ordinary airborne foot motion recovers effort when its retained sprint pace
  is below one. Sprinting air motion keeps its previous no-recovery condition.
- Dead foot and water tasks do not advance the sprint counter or recover/
  consume effort. The original steering path returns before those operations.
  Existing authoritative respawn remains responsible for its reset.
- Swimming effort recovery runs before the swim dynamics step. Tread/breast,
  dive/underwater and shore-exit boundaries use the incoming task state, rather
  than the state the following physics update just selected.
- The breath HUD remains visible while oxygen recovers after surfacing or
  leaving water. It disappears at full oxygen and still appears underwater.
  This is the archived status rule; it changes neither the oxygen capacity nor
  server drowning authority.

`NativeStamina.prepareUnderwater()` and `restForLocomotion(ticks:ratio:)` expose
those shared operations. The latter contains invalid/nonpositive recovery
clocks and nonfinite ratios without changing the raw archived `take`/`rest`
contract. `NativeSwimController.displayBreath` supplies the status boundary.
The actual Renderer uses these helpers in its existing movement owners.

## Evidence and regression

`tests/movement/smoke_native_effort_recovery.py` extracts the current production foot,
swimming and personal-flight coordinator bodies. It uses the existing real
CLP/native-world harnesses with controlled grounded, airborne and water poses.
It does not replace combat eligibility with a test-only predicate.

The independent comparison executes selected recovery, underwater preparation,
budget and status expressions from actual archived module 19737, plus the
actual 34719 sprint and 19863 swim controllers. Complete source, selected ranges,
SHA256 records, native traces and comparisons stay under ignored
`local-only/native-physics/tests/effort-recovery/`.

The scenarios include standing and moving recovery, exhausted underwater
movement, tread→breast, dive→underwater, death/revival, shore recovery, airborne
walking/sprinting and parachute counter retention. Calls cover 15/30/60/120/144 Hz
sized deltas and an uneven schedule. The gate checks budget/oxygen ownership
under those inputs; the separate fixed-frame/world regression gates establish
their own trajectory/cadence boundaries.

The final frozen run passed 104,253 comparison checks across 36 water,
42 foot and 12 flight scenarios, plus 15 invalid recovery-input guards. Both
owned source files and selected production Renderer methods remained unchanged.
This supersedes the intermediate pre-freeze runs recorded below.
The historical Core87 Renderer is supplied only as an optional negative control
against current helpers/world, rather than claimed as a full old app binary. It
reproduced 24,930 differences in 74 scenario groups across the same 104,253
checks. A later run after combat integration also passed every comparison, but
its final source guard detected a concurrent production-marker edit; that
intermediate is retained and is not a frozen acceptance result.

Existing canonical swim/sprint and personal-flight goldens also pass 88,061 and
152,166 comparisons respectively in the Core88 aggregate. New helper entry
points do not alter their raw reference contracts.

## Remaining differences

No authentic stat-dependent capacity/training curves, stamina/lung upgrades,
fat/muscle effects or original progression/persistence were fabricated. The
fixed baseline 150 effort and 1150 oxygen budgets remain browser evidence.
Vehicle/occupant oxygen ownership and complete jetpack effort semantics are
outside the corrected source boundaries. Original-game feel, body trajectories,
physical touch/controller acceptance, hardware FPS and all network transitions
remain separate verification work. No original game executable was run here.

REA MCP/CLI was unavailable in this worker. These are ordinary offline Node
source probes and native CPU regression observations, not new REA Evidence IDs.
The supplied IPA's existing static-resource evidence remains distinct from
original runtime verification. No original scripts, assets or derived fixtures
are part of the public source release.
