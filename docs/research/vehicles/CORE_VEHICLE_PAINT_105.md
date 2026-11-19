# Per-instance vehicle paint

## Native-size vehicle images and hardware sampling (145)

The earlier fixed atlas resized every decoded vehicle image to a 128×128 square.
The new explicit VPC3 family keeps the original base-image dimensions and RGBA
bytes in a bounded staging PNG. Native runtime upload copies those rectangles
to individual original-size Metal textures. No original base texels are
resampled. Hardware sampler states preserve the decoded archived texture
object's wrapping and minification/magnification modes. Requested mip chains
are generated explicitly on the GPU; these are not recovered original TXD
mip images or a claim about a particular retail renderer.

The producer emits a distinct encoding, complete geometry/image digests and
validated layout/sampler metadata. The independent host setup selects this
profile for ordinary and working vehicle families. Existing VPC2 and explicit
legacy WRL2 families retain their previous shaders, paint and atlas behavior.
VPC3 cannot silently fall back to the old atlas shader. Its prepared-install
verifier and runtime share the same material/image/geometry admission check;
short native staging images use exact dimensions rather than a fixed-cell
coverage assumption. Existing verified packages stay usable.

Each draw retains its selected image through paint, lamp replacement, damage,
node transforms and deferred transparency. Different images cannot merge into
one draw. Upload and subsequent rendering share one command queue without a
main-thread GPU wait. Preflight and actual GPU allocations are bounded to
8 MiB per family. Failed or retired bindings skip the draw and retry the
complete family instead of sampling a stale atlas. Draw-range checks avoid
integer-overflow admission. No physics, seating or network pose is replaced.

Authored evidence passes 2,132 actual native/Metal checks over 1,296 offscreen
renders, plus thirteen converter pixel/bounds checks. The same GPU samples are
compared to isolated original-size images across edge/negative/out-of-range
UVs, wrapping modes and all six supported minification modes. Actual prepared
image-verifier methods cover native and legacy dimension admission. Separate
owner-local evidence covers all 212 families: 4,771 producer checks, 4,552 exact
packed-image checks and 6,722 native decoder/GPU readback checks. All geometry
bytes after the encoding marker equal their prior VPC2 families. The largest
observed native texture family allocated 1,994,752 GPU bytes. Every converted
image and original input remains local; current served families were untouched.

The six working families pass 89 complete-family/corruption/output-boundary
checks. A preserved fixture failure revealed a no-op invalid-node mutation when
the first configured model had no working node; the test now selects a concrete
part and requires it. A separate older alpha fixture captured a later world
material branch with an unbound variable; its descriptor boundary is corrected
while retaining the actual deferred encoder and existing pixel assertions.
Earlier private helper entrypoint/channel-order/type-check failures remain
recorded separately. Source checks, complete SDK builds, normal installed-game
acceptance and retail comparisons remain distinct.

Supporting static REA artifact evidence is
`ev_c12be01d7ce7e7c978c5b9cad79b1fca31344d2fa4ae86a5649bf2c448e5f7a4`.
Its semantic coverage is partial after the bounded worker heap limit. The
separate offline factory probe establishes decoded object values; neither
observation is an original retail gameplay recording. Stored TXD mip parity,
advanced paintjobs, reflections, complete lighting/glass fidelity and purple
city gaps remain open. The pink foreground object in the sampler QA captures
is the server-scripted bed model1700; the earlier parked-car label was incorrect. This change
does not establish complete resource coverage or 1:1 GTA San Andreas fidelity.


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
