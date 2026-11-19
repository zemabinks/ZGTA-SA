# Core118 reload audio handoffs

Swimming and incompatible jetpack flight could end a reload animation while
leaving its delayed sound owned by the old task. Selecting another inventory
weapon already canceled that sound; temporarily unarming the animator did not
change inventory selection and missed that boundary.

The Renderer now uses the existing reload cancellation callback after an owned
swim result actually unarms an active reload, and after actual jetpack flight
ends a reload for an incompatible weapon. The existing GVC binding invalidates
queued phases and pending sample completions. Inventory, ammunition, water and
flight equations, animation clocks and committed one-shots are unchanged.

Shallow water, missing output/resources, already-unarmed tasks, rejected flight
and input-only resets do not acquire cancellation. Compatible armed jetpack
reloads continue. Parachute and support-knock phase1 behavior is preserved: the
retained browser also permits those phases, so blanket task cancellation would
not be supported by this audit.

The owner-local focused gate uses real prepared animation profiles/clips,
native character/flight/swim types, actual Renderer methods and the literal GVC
audio binding. Its audio sink and sample scheduler are inert:

```sh
python3 -B tests/audio/smoke_native_swim_reload_audio.py
```

Optional `--historical-root PATH` executes the literal previous Renderer water
and flight methods as negative controls. It is not required for the default
run. The test requires existing owner-local CLP/native physics; it performs no
asset preparation or resource hydration.

The combined current/historical run passes91 checks with1,871 owned animation
clips. The existing real task-handoff gate passes16,049 checks with zero
failures, retaining its motion, pose and timing assertions.

The retained browser comparison verifies reload-capable22/23 profiles and
temporary weapon ownership. It does not establish retail timing or audible
device playback. The existing420ms sound delay remains; full1:1 gameplay parity
is not claimed.
