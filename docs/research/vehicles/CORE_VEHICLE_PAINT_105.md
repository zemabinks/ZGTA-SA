# Per-instance vehicle paint

Core105 fixes the reproduced case where the same `420.6.1.0.` taxi was yellow
in the browser and grey in the native app. It preserves the existing vehicle
geometry, working poses and nonpaint surfaces. Original reference data,
converted families and GPU recordings remain owner-local.

## Cause and correction

The old converter baked a fallback colour into painted vertex RGB. That lost
information, especially intrinsic zero channels, before rendering began. The
native rig then discarded the paint material slot, and the renderer reduced
the full network appearance code to a model ID. A final global tint could not
recover the missing channels or distinguish paint from glass, tyres and trim.

The converter now retains intrinsic RGB on authored paint parts and records
the material slots, original palette, model defaults and applicable variants.
The actual instance appearance selects a linear colour for each part. Own,
remote-driving, parked and train-carriage draws keep their own appearance;
adjacent draw merging also compares paint state. A dedicated Metal fragment
entry applies it without changing the legacy fragment ABI or nonpaint output.
Tagged custom RGB and the four-colour variants used by models446/483/524 are
handled explicitly. Generated train carriages use their own catalogue defaults.

## Versioned assets and host setup

Neutral-painted vertices use rig JSON version2 and binary magic `VPC2`.
Existing version1/`WRL2` families retain their baked rendering path. New families
validate identity, encoding, bounded geometry and indices, finite values,
atlas dimensions and matching binary/atlas/normals hashes. Mixed generations
and attempts to label new neutral geometry as old baked geometry are rejected.

Normal `host.py setup --native` working-vehicle preparation accepts these new
families and retains deliberate old-format support. All six fresh working
exports match the adopted paint overlay byte-for-byte. This matters because
the working-stage directory takes precedence over the ordinary site files.
Replacing only the ordinary files would leave six models on old rendering.

The adopted private candidate contains212 complete four-file model families,
848 files in total. Every served file was fetched through the isolated real
HTTP server and checked against the frozen export hashes; the working-family
overrides were checked too. No shared archive or human-used server was changed.

## Verification and limits

```sh
python3 tests/vehicles/test_native_vehicle_paint.py --prepare
python3 tests/vehicles/test_native_vehicle_paint.py
node tests/vehicles/smoke_native_working_stage.js
node tests/vehicles/smoke_native_working_assets.js
```

The prepare step needs the owner's archived browser assets and creates a local
primary reference. It is unnecessary when that matching reference is already
prepared. Its strict producer checks cover all212 models,867876 vertices,
3007 painted parts and12415 nonpaint parts. The separate native test executes
the real rig and extracted Renderer draw selection:2568 appearance cases,
59742 actual draw packets and251035 checks.

Actual desktop Metal readback checks all256 palette entries and108
independently browser-derived shader cases with zero maximum channel error.
Twenty-four legacy/nonpaint cases remain bit-identical. A complete Taxi
mesh/atlas/pose render changes259 paint pixels while preserving160 visible
nonpaint pixels and alpha. These are actual GPU-to-buffer readbacks, not
inferences from selected uniforms. Existing Renderer, aircraft, train and
working-pose regressions also pass. Fresh working preparation passes95
focused compatibility/corruption checks and102 HTTP checks.

Both full App SDK builds pass: Debug Simulator and optimized Release iPhone.
The latter remains unsigned and uninstalled while the phone is being used by
a person. Desktop GPU results do not establish physical iPhone performance,
retail physics or complete visual parity. General environment lighting,
reflections, optional paintjobs/patterns and finish effects remain separate
work. Live paired scene evidence is recorded separately from these numerical
and build results.

Actual paired acceptance on17 November: the dedicated iPhone12Pro Simulator
joined as an independent guest, took the normal taxi job, entered, drove and
exited. Its native screenshots show the yellow cab before and after driving.
A separately rendered unpatched browser shows one yellow cab during the same
same-ID transition and its final parked restoration. The actual UIKit test
passed, but its handbrake touch failed hit testing because brake/reverse
covered the reused Jump/handbrake frame. Handbrake behavior is not accepted by
that run; it is addressed separately in Core106. The phone was not operated.
