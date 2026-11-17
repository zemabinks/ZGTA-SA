# Vehicle touch ownership

Core105's real Simulator run exposed an unreachable handbrake. Its ordinary
brake/reverse button had exactly the same Auto Layout frame as Jump, which
became the handbrake while driving. Brake was added afterward, so it owned
the touch. XCTest found no valid handbrake hit point and fell back to a centre
coordinate. The runner's successful exit assertions did not verify handbrake
input. This is independent of the earlier human-contaminated phone trial.

Core106 uses a separate road-vehicle handbrake in the free lower-row position
left of the crouch/unhitch control. Its44-point target is separate from brake,
accelerator and working/tow controls. The foot Jump control is hidden while
driving and retains its existing foot/swim/flight handlers when on foot.
Boats, aircraft and trains do not expose the road handbrake. The existing
touch-down, release-inside, release-outside and cancellation handlers feed the
same input owner; connection, modal and application resets remain in place.

The independent UIKit geometry carrier and the actual full game UI are tested
separately. The carrier extracts current production layout/visibility/handler
source, applies explicitly synthetic screen/safe-area cases and includes the
old overlapping controller as a negative. Its default build-only result is
not a runtime pass. The normal full-game scenario joins the isolated server,
starts a taxi job and checks that accelerator, brake/reverse and handbrake are
separate and hittable before touch input. Actual runtime results and source
hashes remain in ignored local evidence. Neither check establishes original
retail braking curves, real controller feel or physical iPhone performance.


## Executed checks

The final asset-free carrier ran on the dedicated QA Simulator and passed
20574 checks across144 explicit layout contexts. It reproduced270 historical
covered-button hit failures from the actual Core105 controller. Both carrier
architectures compile cleanly. The verifier checks current controller, HUD,
stick, Swift test and Python generator hashes; deliberate HUD/stick source
mismatches are rejected. Synthetic safe areas and context records are stated
fixtures, rather than claims that144 physical devices were tested.

The actual extracted input-binding regressions pass3836 checks. The existing
coupling-control carrier initially failed to compile because its button spy
omitted the newly referenced handbrake field. Adding that one spy leaves App
source unchanged and restores all65 coupling/control checks. The failed
compile and an earlier240-second concurrent-build timeout remain preserved;
they are not relabeled as successful original runs.

To build and separately verify a real UIKit run:

```sh
python3 smoke_native_touch_layout.py
# Run only on an explicitly selected QA Simulator using the printed commands.
python3 smoke_native_touch_layout.py --verify-report /path/to/touch-layout-report.json
```

Default compilation reports `BUILT_NOT_RUN` and is deliberately excluded from
the155-case aggregate runtime registry. Without an adjacent Core105 source,
the fresh-clone carrier labels its negative as a controlled restoration of the
old overlap rather than claiming a historical source capture.


The complete Core106 Simulator game passes its normal guest→taxi job→entry→
touch→exit scenario in174.050 seconds. Accelerator, brake/reverse and handbrake
are explicitly hittable with distinct frames. The real handbrake press/release
has no invalid-hit-point fallback. Exiting removes that control and restores
a hittable foot Jump. Separate actual browser frames retain one same-ID yellow
Taxi through occupied/unoccupied handoff and final parked restoration.

The cab had already stopped before the handbrake press. This verifies the
correct reachable target and input path; it does not measure braking
deceleration. Both full App SDK builds pass with181 captured App/resource
hashes unchanged. The optimized iPhone product is unsigned and uninstalled.
The human-used phone and its Core104 world were left untouched.
