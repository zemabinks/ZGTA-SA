# San Andreas native bindings audit

Core81 corrects keyboard defaults and console face-button meanings without
moving the touch controls. It does not claim a complete retail controller
implementation or physical-device verification.

## Evidence and edition boundary

Primary references are the Rockstar PC manual, controls pages 7–10
([archived PDF](https://manuals.plus/m/5380ead53b0aa6aafca6a65464f358a41d8007ddcd5d6c587f0ceb66f7200caf_optim.pdf)),
the official [Xbox 360 manual](https://media-rockstargames-com.akamaized.net/rockstargames-newsite/img/manuals/en_us/GTA_SA_360_MANUAL_ENG.pdf),
and the official [PS3 manual](https://media.rockstargames.com/rockstargames-newsite/img/manuals/en_us/GTA_SA_PS3_MANUAL_ENG.pdf).
These are edition-specific documented bindings, not runtime measurements.
The archived browser's controls screen is secondary evidence; it does not
override these manuals. No GTA V binding is used as a default reference.

## Keyboard

| Context | Binding |
|---|---|
| On foot | WASD or arrows move; Space sprints; Left Shift/Right Ctrl jump; Left Alt requests walking |
| Enter/exit or climb drop | F or Return |
| Weapons | Q previous / E next, Left Ctrl or keypad 0 fire, Delete/Caps Lock aim |
| Crouch / water | C crouches; in water C or fire input dives; jump input jumps/pulls |
| Driving | W/S throttle/brake, A/D or left/right arrows steer, up/down arrows control pitch/lean |
| Aircraft | A/D rudder; left/right arrows roll; up/down arrows pitch |
| Vehicle camera | Q left, E right, Q+E behind; keypad 1 looks behind on foot; V/Home changes perspective |
| Vehicle secondary controls | Space/Right Ctrl handbrake; H/Caps Lock horn; Insert/4 next radio, R/Delete previous |
| Native extensions | J jobs, T chat, M map, G animations, R reload on foot, L lights; Tab invokes the available context action |

The native walking intent uses the existing original walking animation phase;
it introduces no guessed speed. Walking and sprint inputs remain independent,
matching the archived locomotion control boundary. Jetpack descent uses the
jump-held control and C brakes; parachute opening uses fire. Unsupported
vehicle weapons and gang/skill commands are not fabricated.

## Controller

Xbox A/B/X/Y names denote the corresponding PlayStation Cross/Circle/Square/
Triangle positions. A runs/swims, X jumps or pulls, Y enters/exits or drops a
ledge, B attacks or dives. Left-stick click crouches on foot. LB/RB cycle
weapons in both directions. Menu/Start pauses, Options/Back changes camera.

Native LT aim and RT fire on foot are a deliberate modern-trigger adaptation;
they are not presented as the original console shoulder layout. Vehicle analog
triggers retain throttle/brake, left stick steering/pitch, right stick camera,
and shoulders look in road vehicles or rudder in aircraft, without forcing
a simultaneous aircraft camera peek. R3 requests behind-view on foot and
in vehicles (the camera excludes aimed views). D-pad up/down selects vehicle radio stations. Foot
D-pad up reload is an explicitly native extension. Aircraft left-stick click
uses available landing gear; a horn-capable vehicle uses it for horn.

On bicycles, A/Cross charges/releases the verified bunny hop, X/Square brakes,
and trigger pedaling/reverse remains separate. The existing touch fire control
is relabeled for bunny hop in that context. Core82 additionally verifies Left Ctrl/keypad0 for bicycle hop from the original
PC tutorial secondary-fire token and manual. See CORE_INPUT_ACTIONS_82.md. Radio and hop behavior
must not imply unimplemented vehicle weapon support.

## State and integration

`NativeGameBindings` is the context-aware mapping boundary. Its keyboard frame
separates movement, steering, camera look, jump, sprint and aim. Neutral
controllers do not erase keyboard throttle, steering or pitch. Existing
controller neutral rearming is preserved after connection, overlay, background
and vehicle transitions. Gameplay input remains suppressed while a menu is up.

Menu/Escape resume observes a release before accepting a new press, preventing
the button that opened a panel from immediately closing it. Controller menu
handlers are restored on dismissal.

Weapon selection uses the authoritative inventory's slot ordering, rather than
sorting numeric weapon IDs (which incorrectly put grenades ahead of pistols).
Rapid Q/E or shoulder edges advance a requested cursor and serialize real
`weapon.select {weapon:id}` requests. Cancellation drops queued changes while
waiting for the already-sent request; reconnect invalidates the old nonce.
Unknown transport outcomes request authoritative resynchronization. No shop
panel is substituted for weapon cycling.

Radio previous/next uses the actual current station/off ring, including streamed,
local-file and off-only configurations. It does not hard-code an invented new
station count.

## Verification and remaining boundaries

Run `python3 tests/ui/smoke_native_bindings.py`. It compiles the production pure helpers
and executes actual extracted VC context, dispatch and asynchronous equip
methods with controlled HTTP completions. The tests cover opposing keys,
context permissions, held-button edges, cancellation/reconnect/unknown outcomes,
slot ordering, station-ring reversibility, neutral rearming and menu release.
Artifacts/source hashes stay in `local-only/native-physics/tests/bindings`.

The native scene and physical controller still need acceptance checks. Unsupported vehicle weapons and any remaining edition-specific
camera/secondary actions are recorded limitations, not silently remapped to
unrelated jobs or shop UI. Core80 and shared native physics artifacts are not
changed by this audit.

Core82 adds capability-gated melee guard/block and distinct unsupported alternate
intent, plus the modal Escape release handoff; see CORE_INPUT_ACTIONS_82.md.

Native aiming remains the existing free-aim implementation. Retail lock-on
target cycling, scope zoom alternatives and gang/conversation commands are not
introduced by this bindings change. Crouched and free-aim walking retain the
same documented movement, jump, weapon and crouch bindings; the camera applies
its own aimed-view exclusion to behind-view requests.
