# Front melee blocking and independent hit events

Core93 corrects a server/client ownership gap: the native animator could hold
its block pose while the independent server still removed armour or health.
A valid front melee block now returns before damage. Chainsaw attacks, side
and rear attacks and an idle guard stance retain their damaging path.

The independent decision uses the owner-local melee profiles and the archived
client's strict front-angle boundary. Server-selected equipment governs native
defence; legacy equipment comes from its existing walking state. No original
weapon profile data is embedded in public source. Missing profiles disable this
rule until the owner prepares the existing local melee metadata.

## Event and animation ownership

A successful block may leave both health and armour unchanged. Health revision
therefore cannot identify every hit event. The server now assigns a separate
connection-scoped hit sequence before sending an accepted event. Sending that
same event twice preserves its sequence. The native client validates its
connection, sequence and accepted health acknowledgement before invoking the
reaction callback. Malformed identities, duplicates, old connection identities
and unsequenced downgrades cannot replay it. Earlier independent servers retain
the previous health-revision fallback until sequenced feedback is observed.

The native Renderer sends accepted parries to the existing original block
animation instead of playing a damage flinch or cancelling held inputs. Damage
continues to be applied once by health authority. Session changes reset event
ownership. Original browser hit envelopes remain unchanged and positive, so
the archived browser's own block routine still receives its normal input.

## Bounded verification

- The actual archived hurt and direction routines match the independent rule
  over33,849 decisions and39,317 checks, covering47 incoming weapon codes,
  all16 defending melee profiles, heading wrap and angle boundaries. Additional
  malformed-state and missing-profile cases reject invalid defence.
- Actual native HTTP/URLSession/WebSocket and unmodified independent authority
  pass50 native checks and58 server/legacy checks: eight native hits including
  repeated unchanged-health blocks, armour absorption, front/rear/guard/chainsaw
  distinctions, duplicate/malformed/stale event identities and a reconnect
  whose new hit sequence starts at1. A connected native attacker also strikes
  a browser-shaped defender through the real transport.
- The actual Renderer hit-method/animation/motor gate adds active block pulses
  at20/30/60/90/120Hz, retaining input and the block tag without generating an
  attack marker. It passes2,514 checks and1,138 native ticks together with the
  existing stun/death/impulse/knockdown scenarios.

Final acceptance passes99/99 gates with unchanged source, plus Release
Simulator and unsigned generic iPhone builds93. Unchanged native bridge/core
source retains the prior five-link Apple ABI evidence.
Original assets, generated observations and test reports remain local.

## Remaining limits

The server checks the latest received defence state. It does not rewind input
history for latency, and a browser can change its local block between that
report and receipt of a hit. This pass does not establish exact WAN parry
behavior, fighting-style counterblows, original damage balance or hitboxes.
Rendered animation, physical touch/controller use, retail gameplay comparison
and iPhone performance remain separate open acceptance requirements. No1:1
accuracy is claimed.
