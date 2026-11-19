# Landing completion owns the gait restart

Ordinary animated landing now restarts the shared walking, running and
sprinting clock when that landing action completes. The completion capability
belongs to the landing owner, rather than to a clip name used by another task.
Replacing or cancelling that owner, death, missing landing clips, knock/get-up
and unrelated action completion do not inherit the restart.

The retiring step finishes its existing root-motion calculation first. Changing
the clock between the before and after samples could otherwise invent reverse
motion or an extra cycle. The next animation step starts from the new gait
origin. Crouch/strafe clocks, blend weights, sprint, physical state, input and
network authority retain their existing owners.

```sh
python3 tests/movement/smoke_native_landing_gait.py
```

The gate uses the actual CLP decoder and animation implementation with authored
clips, movement modes, frame schedules and interrupted actions. An optional
historical root must fail the specific retained-phase assertion after successful
compilation. CPU task-state acceptance remains separate from rendered landing,
retail timing, physical controls and multiplayer scene acceptance.

This is an intentional original-first task-policy correction. An unmodified
archived-browser comparison retains its older gait clock after landing and is
therefore not an equality oracle for that transition. No broader animation or
physics equality is claimed.
