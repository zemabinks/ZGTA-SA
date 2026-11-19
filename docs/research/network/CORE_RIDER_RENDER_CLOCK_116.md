# Rider pose elapsed time

The separate rider pose clock retains ordinary active draw intervals through
0.5 seconds. The shared fallback, remote foot and bike clock keeps its existing
0.1-second cap. Only the four `NativeRiderPlayback` draw callers use the new
interval API; gameplay physics and input clocks are unchanged.

Each successful pose draw owns one monotonic interval. A newly admitted
enter/leave/sit command intersects it with the command's own timestamp. Commands
observed during a draw start at that draw; a local exit requested between draws
starts at its input time. A newly created owner cannot consume older draw time.
Remote duplicate actions and ignored default actions while entering do not reset
the command epoch. Existing vehicle/model/seat/actor cache keys remain in charge
of remote owner replacement.

A raw active draw gap over 0.5 seconds is rejected before command intersection.
Backward/nonfinite/inactive samples are rejected too. Rejection reaches the
existing rejected-delta path: it does not become a valid zero, which can consume
missing or zero-duration phases. The next interval starts from the latest sample;
there is no queued suspension debt. First draws and fresh session resets start
at valid zero. Existing application resign/return hooks rebase the new clock
through `resetDisplayClock`; a draw after return admits only time after that
floor. The draw also checks application activity and window attachment.

For an admitted interval at most 0.1 seconds, Playback calls the unchanged direct
delta consumer exactly once. Larger admitted intervals use greedy 0.1-second
slices and a remainder, bounded to five calls. Input stays fixed during these
slices; no renderer callback runs between them. The returned final frame keeps
its final sample/state/turn/transition/transitioning/door fields. The last nonnil
capture, final capture serial, and terminal door release are folded across this
invocation only, then expire normally. A numerically empty tail is skipped.

The interval clock is sampled at `drawActors`, after drawable/encoder creation.
An owner skipped by visibility or resource guards receives only the latest
global interval when it becomes eligible again; it does not accumulate a
per-owner invisible clock. A failed draw before `drawActors` makes no pose-clock
sample. A subsequent ordinary gap may be admitted; a discontinuity is rejected.

`tests/vehicles/smoke_native_rider_timed.py` executes the actual CLP1 reader/planner/Playback
with invented tracks and literal renderer clock, command, cache and completion
blocks. Its default run needs no game assets or historical checkout and reports
`historicalExecuted: false`. Optional `--historical-root /path/to/frozen-checkout`
adds literal Core115 source controls and a direct-consumer byte comparison,
reporting `historicalExecuted: true`. It uses injected monotonic timestamps and
local asynchronous-dispatch adapters. `tests/vehicles/smoke_native_rider_clock.py`
continues to check the original direct consumer separately. No pose golden,
phase duration, animation Euler formula or phase plan is rewritten.

These are source/CPU regression checks. Repeated legacy Euler steps retain
schedule-dependent response; they do not prove equal curves across frame rates,
retail timing or rendered acceptance. No historical input is reconstructed
inside a long interval. Metal posing, physical vehicle motion, actual UIKit
lifecycle order still requires normal runtime checks. A queued vehicle-exit
completion now retains its vehicle generation and weak Playback identity; it
runs only while both still match a driving owner. Reset, authoritative placement,
revocation and new entry invalidate an already-dequeued old completion. The
source regression reproduces the old unguarded callback reaching a replacement
owner and verifies the guarded path. Raw occupied-vehicle teleport behavior is
preserved; it is distinct from authoritative placement/revocation.

The frozen Core116 application also passes full iPhone Release (arm64) and
Simulator Debug (arm64 and x86_64) SDK builds. A normal Simulator update matches
all five executable/Metal/plist payload files and preserves the four committed
resource metadata files. The supported GAME FILES repair then verifies the
6,773-resource package while retaining installed mode. Normal official open.mp
class0 admission, CJ Spawn and ordinary camera input pass; a full Simulator
capture shows CJ and the world. The scripted stock cone is not identified in
those captures and is not counted as rendered acceptance. This does not exercise
a long rider interval, physical device or matched retail animation timing.
