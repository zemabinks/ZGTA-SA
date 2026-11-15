# Held parachute equipment

Selecting weapon 46 previously drew the folded `gun_para` bag with the right
hand transform used for ordinary guns. The archived browser's `60662.Ko`
attaches that model to animated `SPINE1` (bone 3), with local translation
`(0.1,-0.15,0)` and Y rotation `π/2`. `NativeWeaponAttachment` and the held-model
draw now use that composition. No weapon muzzle/event transform was changed.

The actual bag root has identity rotation/scale before the holder sets those
values. Its native exported vertices retain the DFF-local basis. The transform
is therefore actor-to-world × animated spine × translation × rotation × vertex;
it must not acquire another world-axis conversion, floor adjustment or half turn.

`Ko` first requires `R_HAND` (bone 24). If the rig lacks `SPINE1`, it attaches
the unmodified bag to that hand; if the hand is absent, it attaches nothing.
The native fallback preserves that behavior when the full pose is unavailable.
Twin ordinary guns retain their existing left-hand rotation and muzzle logic.

## Visibility and equipment transitions

The archived local-player effective selection (`19737`'s `t8`) is:

| State | Effective held weapon |
| --- | --- |
| Swimming | 0 |
| Jetpack flying (states 12/13) | Selected weapon only when its actual `flags.arm` is true |
| Grounded worn jetpack (11) | Current selection |
| Parachuting (1–9), landed canopy (10), normal walking | Current selection |

The flag is a weapon definition property; it is not simply "all pistols".
The held draw applies the jetpack rule to the local player. Browser remote
holders use the effective weapon received on the wire; sender selection and
visibility must remain consistent rather than forcing 46 for every chute state.

The independent native server currently stores parachutes in `flightGear`,
separate from ammunition inventory. Native automatic chute state 1–9 therefore
uses an explicit bridge policy: carry 46 during the chute and restore the saved
ammo selection afterward. `effectiveWireWeapon` now feeds both the native held
model/cache and outgoing weapon field, with the original swim/jetpack filter.
Previously that wire said 46 while the native model could still draw the old
gun. Actual flight clips do not hide that model by themselves. The browser's
full utility slot, mid-chute weapon cycling and consumed-bag selection reset
remain unported; this bridge policy must not be described as full inventory
parity.

Automatic dive calls the original inventory's `give(46,1)`, which selects its
slot. That is why an ordinary dive initially carries the folded bag. A later
selection can change it. Open-canopy touchdown or entering water with an opened
canopy drops 46; dropping resets selection to 0 only if that slot was selected.
Owning a parachute, selecting 46, drawing the folded bag, wearing a jetpack and
drawing an opening/landed canopy are separate states. The canopy/jetpack remain
the existing `NativeFlightAnimation`/`NativeFlightAssets` draw path.

## Verification

Run `python3 smoke_native_weapon_attachment.py` with the existing local archive.
The offline reference executes the actual archived holder, R6 animator,
inventory and selection function with the real pedestrian rig/animations and
folded-bag geometry. The Swift comparison runs the real native rig parser,
animation/pose and attachment math; only unused GPU buffer storage is replaced.
It covers walking, weapon switches, all 13 flight states, stop/resume, swimming
visibility, missing bones and a late asynchronous model callback after holster.
It also checks all archived weapon definitions against the actual selection
function. Mesh measurements and original files remain under ignored `local-only/`.

The native policy gate extracts the actual renderer computed property and foot
visibility getter, checks 44 definitions across 14 flight/nonflight states and both
swim states, and exercises actual native flight blends. The real-rig replay
includes 45 collapsed frames and recovery. Results are written to the local report;
the latest verified geometry run compared 5,320 real transformed bag vertices over
480 frames, with maximum error 0.000173 m from the archived holder.

This is a public-browser geometry/selection regression, not a claim of retail
executable equivalence. The supplied PC executable was not run. Physical iPhone
presentation, multiplayer delivery and all other equipment behavior require
their separate acceptance checks.
