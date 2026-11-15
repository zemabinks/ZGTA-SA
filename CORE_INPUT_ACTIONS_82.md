# Core82: original PC actions and modal key handoff

This pass extends the Core81 default-control audit. It changes input intent and
ownership, not movement constants, collision shapes, weapon damage or skill
formulas. Core81 remains frozen.

## Original data evidence

The owner-supplied installer's `text/american.gxt` was selectively extracted,
without running either Windows executable. The local parser validated all127
tables and16,588 entries. Original text stays under ignored
`local-only/research/pc-actions`; it is not bundled or published.
Its SHA256 is`d6e2566d7b85d1b6f913938bf672c0915dfc5db08d6ec826eecffda2ba21589f`.
The disc's scene-image provenance remains documented in the reference inventory;
these data observations do not independently certify a pristine retail dump.

The INTRO1 entry with hash`0xCDC2CE10` identifies the hold/release bicycle-hop
action as `VEHICLE_FIREWEAPON_ALT`. The [Rockstar PC manual's vehicle controls](https://manuals.plus/m/5380ead53b0aa6aafca6a65464f358a41d8007ddcd5d6c587f0ceb66f7200caf_optim.pdf)
assign secondary fire to Left Ctrl or keypad0. Those keys now drive the existing
separate bicycle-hop intent. They do not become handbrake, an on-foot attack
while riding, or a fictional vehicle weapon. Space/Right Ctrl remain brake.

The MAIN entry with hash`0xD095120D` identifies target-plus-jump as block and
target-plus-enter/exit as special attack. The manual supplies the corresponding
PC defaults: Delete/Caps Lock for target, Left Shift/Right Ctrl for jump, and
F/Return for enter/exit. These original-data instructions corroborate action
semantics; they do not identify a special-attack animation or damage formula.
The already documented console bindings remain edition-specific.

## Melee intent

Raw aim becomes guard only when the renderer reports a compatible loaded melee
profile with actual guard support. It does not enable the gun aiming camera.
Holding jump while guarding supplies block intent and suppresses the ordinary
jump edge. Profiles without guard capability retain ordinary jumping. The
existing touch aim/jump positions provide the same guard/block intent.

Simultaneous keyboard keys are collected before their actions are dispatched.
This prevents unordered aim-plus-Shift batches from jumping before the aim
modifier is visible. Pad LT-plus-X likewise uses the current poll's aim state.

Guard-plus-F/Return/Y carries an explicitly separate alternate intent, rather
than entering a car or substituting a normal strike. Its execution remains
unsupported until an authentic profile/animation mapping is established; the
controller reports that limitation. Repeated primary strikes, moving strikes
and prone-target strikes remain selected by the source-backed melee/animation
task. No invented ground-attack button or combo index is introduced here.

Both keyboard/pad and touch-held polling recognize native **gun and melee**
timing. A held button sends one initial request, then keeps the raw held flag
available to that state machine. It does not refresh the melee request buffer
every display frame. Release/re-press creates another edge. The combat gate
also accepts eligible melee timing while a jetpack is worn on the ground,
without allowing unsupported airborne pack, chute, swim or climb combat.

Touch gun aim keeps its own toggle ownership: neutral hardware cannot clear
it. Hardware aim transitions take ownership when actually pressed/released.
Melee selection always clears the gun camera aim.

## Escape defect and fix

The parent's installed optimized Core81 Simulator trial reproduced a pause menu
that swallowed the first distinct Escape after opening. The source copied the
opening key-down Boolean into a new edge detector in `viewDidAppear`. If the
opening release had already gone only to the presenter, the panel incorrectly
believed Escape remained held. Its next press merely waited for another release.

Core82 shares one modal-key handoff object between presenter and panel before
presentation. Either responder can record key-up; appearance does not reseed
or overwrite it. Presenter cancellation/background handling releases the same
state. Opening-key repeats remain suppressed, while the first new press after
the observed release is accepted. Controller Menu keeps its existing physical
release-edge handling.

## Verification and limits

Run `python3 smoke_native_bindings.py`. It compiles the production pure helpers
and actual extracted keyboard/panel dispatch, asynchronous equip, bicycle,
held-trigger and combat-eligibility code with controlled adapters. Tests cover
modifier batches, guarded jump/special handling, supported/unsupported profiles,
presenter/panel release ownership, modal repeats, touch aim, native request edges,
PC secondary-fire hop, station cycling and ordered inventory selection.

This is code-level evidence, not a claim that the mocks execute UIKit or that
a physical controller has been verified. Simulator/device acceptance remains
the parent's separate step. Retail target-lock behavior, alternate-special
animation selection and unsupported melee acquisition/damage policies remain
explicit gaps. No motor, Rust/C ABI or shared library change is part of this pass.
