# Community source release validation

Current Core106 evidence is recorded in `docs/research/vehicles/CORE_VEHICLE_PAINT_105.md`,
`docs/research/vehicles/CORE_VEHICLE_PRESENCE_105.md`, `docs/research/ui/CORE_TOUCH_OWNERSHIP_106.md` and
`docs/development/CORE_GAMEPLAY_JOURNAL.md`. Both complete
Simulator Debug and unsigned iPhone Release builds pass. Vehicle paint,
fresh-host migration, archived browser presence and actual native/server wire
regressions and the actual paired Simulator/browser taxi transition pass within
their documented boundaries. The current phone remains
on Core104 while a person is using it. Core103's149-case composite acceptance,
Core104's focused additions and Core105's affected checks are separate records;
there is no single all-pass155-case run or full original-game certification.

Historical core acceptance,15 November2026:85 Swift source files,34 core regression
gates, matching optimized universal Simulator and unsigned ARM64 iPhone builds.
The installed79 Simulator was used for city climbing/visibility, car controls,
entry/exit and owner-radio station switching/download checks. Literal sphere
queries pass all five Apple ABI targets and the real-city boundary corpus.
Original radio import has separate actual-recording and native offline sample
proofs. See `docs/development/CORE_GAMEPLAY_JOURNAL.md`, `docs/development/CORE_RETAIL_REFERENCE.md` and
`docs/development/guides/RADIO_OWNER_IMPORT.md` for the exact evidence and unresolved differences.

The following75-source checkpoint is historical; its broader old checks are
not represented as new physical-device or original-runtime acceptance.

Verified on 15 November 2026. This records the tested 75-Swift-source native
boundary and the community hosting tools; it does not certify a full 1:1 port.

## Hosting and source separation

- Anonymous HTTPS clone succeeds without GitHub authentication.
- All reachable source history passes the public-path and credential-pattern
  check. Downloaded game files, generated native data, player saves, credentials,
  compiled libraries and local toolchains are excluded from the source tree.
- The release guard rejects a private file even after it has been deleted from
  the newest commit.
- Synthetic clean-host tests pass guest play, local/LAN startup, join-code
  checks, Host/Origin checks, HTTPS-proxy cookie behavior, source links and
  asset-only imports. No real player data is used.
- A separate source/content checkout regenerates the 212-vehicle, nine-dealer,
  29-property catalog and passes multiplayer/gameplay/persistence checks.
- GitHub Actions runs the source-history, clean-host and mocked Discord checks
  on Linux. See the repository's Actions tab for each exact commit result.

## Native builds and runtime

- Optimized Release builds pass for the universal ARM64/x86_64 Simulator and
  generic ARM64 iPhone target with no compiler diagnostics.
- All 110 captured App/resource/Rust/header/library hashes remain unchanged
  throughout those builds.
- The iPhone 15 Pro Simulator loads the original local city, pedestrian,
  vehicle, HUD, radar and map. Guest account restoration, keyboard movement,
  owned-car recall, entry, driving, exit, parked handoff and the native source
  menu are checked. A held touch reverse action could not be dispatched by the
  UI automation, so keyboard reverse was used for that check.
- The standalone numerical/GPU gates cover the source-correct deferred-mass
  core, friction rules, parked lifecycle, vehicle/pedestrian motion, rider
  transitions, contact audio and particle systems. FEATURE_MATRIX.md records
  their measured coverage and remaining contexts.
- A separate empty native setup installs the pinned official local Rust
  toolchain and all five Apple targets, checks the iPhone Metal compiler, builds
  the pinned core from an empty Cargo cache, and passes its C FFI smoke test.
  Missing/stale library stamps are detected. Global Rust and shell profiles are
  unchanged.

Generic device builds are unsigned. Physical iPhone/controller gameplay, frame
rate, original-radio listening, a real public internet deployment and every
remaining gameplay interaction are not certified by these checks. Original
station recordings and the publisher's private multiplayer backend are not
included. Consult FEATURE_MATRIX.md before treating a subsystem as complete.
