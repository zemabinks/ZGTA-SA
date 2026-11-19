# Lost-water vehicle release

Native buoyancy exposed a lost-water flag, but gameplay never released its
occupant. Bikes without a buoyancy solver also lacked the source's separate
submersion fallback. The native getter now preserves the buoyancy owner's flag
when present. Otherwise it compares the current physical body's Y position plus
model origin and0.4 against base water height, using the original strict
boundary. Surface flotation alone is not a lost vehicle.

After completed-wreck handling and before bike ejection, gameplay releases an
occupant from a lost-water vehicle through the forced foot handoff. It preserves
health, clears the old movement association and restores the native foot owner,
whose following tick can enter swimming through the existing water controller.
A water exit does not manufacture crash damage or a death.

The actual archived getter matches7,420 controlled cases using all212 model
origins at Float32 threshold boundaries; the current native getter adds an
absent-definition case. Real exit-method/physics checks include submerged bike,
BMX and Sanchez release. Actual native HTTP/WebSocket and server plus a legacy
observer separately verify living water exit, parked hull state, re-entry,
subsequent wreck death and respawn without reviving the wreck.

These are bounded getter, native physics/method and protocol tests. They do not
establish every rendered water-entry scene, original exit-clearance plan,
passenger behavior, retail feel, controller hardware or device performance.
Final combined validation is recorded in [Core97](../validation/CORE_GAMEPLAY_FOUNDATION_97.md).
