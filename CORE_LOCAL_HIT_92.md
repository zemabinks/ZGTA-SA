# Local hit response and knockdown synchronization

The native client updated health and status on a hit but never dispatched that
event to the local reaction animator. Remote reactions inferred a health drop,
while the victim could keep moving without the original directional flinch or
stun. Native also decoded other players' knockdown tags without publishing its
own. A locally knocked character therefore appeared upright to other peers.

Core92 connects accepted hit events to the actual native response, animation
and fixed motor paths. Health authority stays in `NativeMultiplayerClient`;
the response never subtracts damage again.

## Decisions and ownership

`NativeLocalHitReaction` independently implements the observed archived
pedestrian hurt decisions: directional partial reactions, limb/torso stun
clips, cooldown boundaries, task-specific stun downgrade, quiet hits, selected
death clips, finite death impulses and supported head-loss masks. Its clock is
monotonic milliseconds. The ordinary foot motor consumes a fatal impulse once,
after a climb/swim owner yields, using the existing physics-axis boundary.

The server supplies event-time attacker position and prior life only to peers
that negotiated health acknowledgements. Legacy hit field sets remain
unchanged. The native decoder validates its feedback inputs and otherwise uses
the tracked attacker position. Head piece9 is preserved. A hit is delivered
only after its health acknowledgement is accepted in the current connection;
duplicate revisions cannot replay the reaction.

A status snapshot can arrive before the matching hit. Prior life and accepted
health distinguish that hit from an already dead actor or a pending local fall
loss. If the snapshot already started a generic death pose, the authoritative
cause corrects its clip while preserving elapsed animation time. The next
ordinary motor tick consumes any associated impulse. This does not rewind or
replay physics history.

Successful knock actions retain the original six down codes while floored,
including get-up, and publish0 on recovery. The real Game controller forwards
the animator's tag through native position packets to the existing server row
and browser-shaped peer. A rejected knock does not replace the active code.
Session and relocation boundaries discard obsolete pending damage motion.

## Verification boundaries

- `smoke_native_local_hit.py` executes the actual archived hurt method and
  reaction helper with controlled actor/animator/effect callbacks. It compares
  1,780 decision frames and12,532 checks, with zero measured numeric error in
  those fixtures. It does not run a retail game or rendered scene.
- `smoke_native_hit_runtime.py` compiles current Renderer methods, the actual
  decoder, real local animation clips and native character physics. It checks
  partial versus stunned input, animation-owned travel, death-clock correction,
  one-shot physical impulses, head masks and all six knock/get-up codes across
  display rates. A display frame with no motor tick is handled explicitly.
- `smoke_native_hit_backend.py` uses actual HTTP/URLSession/WebSocket and hit
  authority with synthetic floor geometry and actors. Two accepted hits cover
  deliberate duplicate outgoing event delivery, status-before-hit ordering,
  matching health/reaction ownership and legacy knockdown/recovery rows.
- Existing health, fixed-velocity, climb, connection ownership and gameplay
  gates retain their separate regression coverage.

Final acceptance passes **97/97 gates**, captured sources unchanged, Release
Simulator plus unsigned generic iPhone builds92. The animation/physics gate
passes2,179 checks and1,138 native ticks; actual transport passes13 native and
10 authority/legacy checks. The unchanged bridge/header/core retains the prior
five-link Apple ABI evidence. Reports stay under the owner's ignored
`local-only/acceptance-core-92` directory.

## Remaining differences

Damage policy remains the independent server's policy. Complete original body
hitboxes, headshot authority, front melee parry/counterblow authority, detailed
fire/spray actor effects, driver reactions and all original death/ragdoll
behavior are not established by this change. The controlled hurt gate does
not claim those excluded effects or style-specific asynchronous counterblows.

Original retail comparisons, rendered browser/native scenes, physical
touch/controller handling and iPhone performance remain unverified. Original
assets, archived code, captures and reference outputs stay local. No1:1
gameplay accuracy is claimed.
