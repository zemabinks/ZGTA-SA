# Jump launch association ownership

The launch-foot choice now uses the last evaluated walking, running and
sprinting associations. An idle owner cannot select a foot from its random
initial gait phase. Missing clips do not manufacture active associations.

Selection uses gait priority, the association blend threshold, a phase offset
and a strict wrap boundary. The threshold comparisons intentionally differ:
an exactly-threshold higher-priority association can remain selected without
supplying a phase. Float association math preserves that boundary. The launch
delay, clip speed, physical impulse, movement integration and network authority
are unchanged.

```sh
python3 smoke_native_jump_launch.py
```

Authored CLP fixtures cover idle/cold owners, active gait phases, threshold and
wrap edges, missing/shared clips, frame schedules and a jump interrupting a
landing. A historical root must compile and fail the specific idle-phase
assertion. The gate uses a read-only task-lifetime observer; the animation
algorithm is otherwise compiled unchanged.

This original-first task-policy correction intentionally differs from the
archived browser's raw phase choice. It does not establish retail launch timing,
body-stat modifiers, slope restrictions, rendered or physical-device parity.
