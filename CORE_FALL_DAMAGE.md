# Core86 regular-foot landing damage

Regular native foot falls previously tracked their peak speed and selected a
hard-landing animation without applying damage. Actual current Renderer,
original local animation and native Rapier floor probes reproduced this at
3/10/30m and30/60/120Hz. A10m fall played collapse; a30m fall played ko_skid_back;
both retained100health and no death state.

This repair restores the archived browser client's explicit regular-foot
landing damage step. Its formula and thresholds are a browser compatibility
policy. No retail executable/runtime drop comparison has established them as
original GTA SA calibration.

## Inputs and ownership

`NativeFallDamage` consumes the maximum sampled downward motor speed and the
previous foot task's requested horizontal speed, both in world units per second.
The archived caller uses its previous returned displacement divided by the
fixed delta for the horizontal term. The native `footAirVelocity` already holds
that quantity. Grounded committed velocity would be the wrong input because
the collision has stopped it before the landing callback runs.

The source policy triggers above18.75 downward or33 horizontal speed. Above30
downward its amount is165; otherwise its two terms use the source2.64/.66 gains
above12.5. The actual archived expression is executed by the test runner rather
than replaced by another handwritten reference formula.

Damage runs in the existing consumed-landing branch before its fall history is
cleared. It publishes a lower health once through `onLocalHealth`; repeated
ground ticks do not repeat the event. Environmental fall damage bypasses armour.
The native integral-health boundary rounds surviving health as the existing
server does, while preserving the source's fatal-below-one check before rounding.
The reproduced18health−17.2damage case therefore dies with0health rather than
being rounded back to1. Fatal damage starts the existing death animation in the
same animation tick.

Input cancellation preserves genuine airborne fall history. New climb, swim and
flight ownership clears obsolete ordinary-foot history using the existing task
handoffs. Collision geometry pauses retain physical state and perform no damage
tick; reset/teleport ownership is handled separately by the existing coordinator.

## Evidence and regression

The actual archived factory19737 hash is
`4eb2f2ce8f593a05f6514eb207d23643afbb81b9832dd2509bd9bf8d5a0636a7`.
Its selected landing expression occupies1743820..1743923 and its hurt method
1722358..1723843 (exclusive ends, offsets within `factory.toString()`).

Bounded REA static parent evidence
`ev_31ee76d0c04554fed47e24fd1823dcc058b54d36d74a5dbbec98a3985e2cfd39`
parsed two selected files/1,596bytes with zero parse failures. It establishes
static syntax only, with partial/unknown semantic coverage. The hurt method has
an inert object wrapper. The preceding failed truncated-expression analysis is
retained privately and is not affirmative evidence.

Run:

```sh
python3 smoke_native_fall_damage.py
python3 smoke_native_climb_runtime.py
python3 smoke_native_task_handoffs.py
python3 smoke_native_character_transitions.py
```

The fall runner extracts and executes the actual landing expression, then the
actual hurt method with controlled non-fall visual/death sinks. It compares
17,424 speed pairs and five starting-health values, explicitly checking armour
retention. Native integration uses the current extracted Renderer methods, real
local CLP animation, the actual character motor and accepted native Rapier.

Twelve drop/cadence cases cover3/10/30m at30/60/120Hz and uneven display timing.
They produce100/83/0health respectively, with no event for the safe drop and
one event for each damaging landing. Per-fixed-tick feet, rising speed, health
and fall history agree between display schedules. Further cases exercise exact
threshold edges, horizontal-only impact, repeated contacts, already-dead tasks,
input cancellation and climb ownership. Private pre-fix/final traces, excerpts
and replay source remain under `local-only/research/`.

The final focused gate passed226,980 checks. Its controlled archived-expression
and hurt-method replay is retained as
`ev_13e984b46dee436f0f9bc7e1dd6aa3dd71622db6c69098bee9892eeee931ff79`
with exit0. The owned process group was verified; one process identity was
withheld by the platform, so complete image binding/cleanup is not claimed.

## Remaining limits

- Retail thresholds, character-stat effects, original damage response and
  edition differences remain unverified; no community implementation was copied.
- The archived spawn/show-immunity flag has no exact native equivalent in this
  repair. It is not silently inferred from unrelated teleport state.
- Full native animation assets are required by this existing foot-task path;
  the basic missing-assets fallback remains incomplete gameplay.
- Network stale-vitals reconciliation is a separate integration fix. A correct
  local landing event alone does not prove reliable server reconciliation.
- Controlled floors establish the tested ownership/cadence behavior, not every
  world slope, vehicle impact, multiplayer authority or physical-device result.
