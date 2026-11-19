# Missing-water input ownership

When an active swimmer lost its current water query, the native renderer
processed swimming input, spent its sprint tap and changed facing before
`NativeSwimController.step` completed the task. Ordinary foot control then
received the same tick and could turn again.

The renderer now retires that already-certain completion before swim control.
Water-only dive/jump pulses expire, while current stick input and the unspent
sprint tap remain available to the succeeding foot task immediately. The
retirement adds no oxygen recovery or animation update and preserves the
incoming ordinary-foot motion. A held haul retains its root and clock when
the current water query disappears.

The change preserves the existing missing-depth completion policy. It does
not retime shallow-water countdowns, negative-depth exits or completed hauls.
An afloat support currently also makes the renderer's depth unavailable; its
existing immediate completion is preserved, not asserted as original boat
support behavior. Broader original buoyancy latching, exact retail task-tick
ordering, physical heading integration and shore feel still need verification.
The browser's one-tick control preparation is not imposed on native input.

`python3 smoke_native_swim_retirement.py` runs598 checks across52 authored
boundary/haul cases, using the actual extracted renderer method, swim,
locomotion, heading, sprint and CLP implementations. It covers several positive
frame durations, headings around the angle seam, missing queries, afloat
support, same-tick foot response, sprint ownership, water pulse retirement,
animation clocks, haul continuation, invalid clocks and nonmissing queries.
Its character output and water queries are controlled boundaries; it does not
run the collision world, GPU, multiplayer scene or a retail game.

The optional `--negative-root` compares a retained historical renderer, which
must compile and fail the specific outgoing-facing check. Compilation failures
cannot count as a reproduced regression. Full SDK builds, ordinary gameplay
acceptance and device comparisons remain separate from these source gates.
