# Remote character presentation time

Remote foot animation now owns its display clock per character. Ordinary active
intervals through half a second are retained and advanced in steps no larger
than one sixtieth of a second. The character's network position, local motor,
movement speeds and transport packets are unchanged.

A newly created character starts at zero elapsed time. Leaving visibility,
application suspension, disconnect and model replacement cannot donate an old
draw interval to a new owner. Backward, non-finite and long-gap samples do not
replay background time. A valid resume observes the current snapshot at zero
elapsed time before advancing again. The direct delta animation API retains its
existing contract.

The bounded interval uses the currently observed controls. Position and heading
are interpolated between observed endpoints so repeated substeps do not create
a false jetpack velocity impulse. This is presentation sampling; it does not
invent authoritative packet timestamps or establish the exact time of an
unobserved task change.

The final pose is drawn once. Travel, footstep and projectile events are retained
across all admitted steps. Parachute targets are passed to the actual canopy
pose operation in order, including target disappearance and landed-anchor
retirement. Combining easing factors against only the final moving target would
lose the intermediate poses. Held frames clear their event/target sequences.

Run the portable CPU regression with:

```sh
python3 smoke_native_remote_foot_clock.py
```

The gate compiles the actual CLP reader, animation controllers and literal
Renderer clock/attachment dispatch against authored tracks. It covers slow and
jittered schedules, ownership resets, invalid clocks, traversal presentation,
single/twin/stream firing, reload/switch boundaries and moving canopy targets.
An optional `--negative-root` checks the earlier capped implementation. Optional
`--owned-library` and `--owned-definitions` inputs provide separate private
reference-data checks; those files and results are not published.

These checks establish bounded scheduling and dispatch behavior. They do not
establish retail input timing, rendered foot contacts, exact canopy bones,
physical-device performance or complete gameplay parity. Real multiplayer
scene acceptance remains separate from the CPU gate.
