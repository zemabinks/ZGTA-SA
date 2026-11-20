# Native character materials and stock rig preparation (150)

## Reproduced character-rendering defect

The shared RenderWare fragment shader samples a material only when its uniform
texture-presence field is enabled. The skinned-character encoder bound its
original texture but always wrote zero to that field. Imported CJ/custom skins
could therefore draw without their texture even though acquisition, rig import
and GPU image-byte tests passed.

An authored fixture reproduces the failure with the actual skinned encoder and
shader: the character ignores its bound red texture. A static-render control
uses the same material and the actual actor's posed vertex positions. Earlier
fixture initializer/idle-header errors remain retained separately from this
intended GPU failure.

The skinned encoder now follows the common material contract: texture presence,
texture/sampler overrides, optional material modulation, explicit color,
vertex-color suppression, alpha cutoff and blending overrides. The vertex
shader consumes the suppression flag. Legitimate untextured materials still
skip sampling, including when a border sampler is bound. Current and historical
pixel regressions distinguish these cases; the focused current gate passes
70 checks over 28 actual static/skinned Metal renders.

## Stock pedestrian CPU resource boundary

`NativeStockPedLoader` acquires stock rig/dictionary files through the existing
verified file loader. It validates exact model/dictionary identity, source
origin, paths, advertised sizes, CRC32 and SHA-256. The pedestrian path requires
child-before-parent dictionary precedence. Static object loading retains its
own entry point and behavior.

One active rig job and a bounded pending queue feed a serial utility decoder.
Cancellation retains the active slot until the work actually exits. Resetting
this owner does not reset the shared verifier or cancel another object's file
request. Source/generation/request identity is checked before preparing a ready
receipt. The actual native rig and material parsers reject incompatible or
incomplete data; they do not substitute a static model or a T-pose.

The encoded source, decoded dictionaries and prepared family have distinct
limits. The 64 MiB prepared-family accounting includes mesh, textures and SKN1
bytes; it is not a claim about total process RAM or allocator overhead. Original
available image dimensions, pixels, sampler declarations and stored mip levels
are retained. No unavailable mip or model is invented.

## Current evidence and remaining integration

- Authored HTTP/local acquisition, rig/material preparation and actual GPU mip
  readback pass 193 checks with 13 distinct callbacks and 6 image-level readbacks.
- The expanded local three-model gate passes 221 checks, 16 callbacks and 9 GPU
  image-level readbacks. `bmori`, `army` and `wmopj` retain 393,216 original RGBA
  bytes; all original input hashes are held. Their saved SKN1 integer fields
  match and maximum floating-field error is below 1.27e-19. This compares our own
  resource representations, not an original retail gameplay replay.
- The initial original-file fixture was correctly rejected because development
  mirror links resolved outside its declared source root. Private copy-on-write
  fixture files fix the setup; containment validation is unchanged. Both results
  remain retained.
- The existing static asset-loader gate passes 123 checks over 56 cases plus four
  original prop/four external-COL cases. Its initial missing local reference is
  retained; restoring the existing reference link does not change an assertion.

The new stock CPU loader does not itself register an ordinary pedestrian in the
game renderer or close the missing canonical-skin inventory. Existing CJ and
custom-skin rendering use the repaired material encoder. Full source/SDK,
normal installed CJ before/after, physical-device and retail acceptance remain
separate gates. World fog/day-night policy for this raw draw path, ordinary
raw-family GPU registration/cache admission, supplemental canonical mappings,
ambient AI, traffic and police remain open. Original files, derived fixtures,
captures and private histories stay local.

## Full selected source regression and normal baseline

The full selected Metal/physics/audio/transport chain passes in 851.1
seconds. All 227 App/build inputs and six captured test sources remain held;
project, hosting and repository-layout checks also pass. The intended old-ped
texture-pixel failure, current authored/three-family preparation and actual
original-ped animation gates remain distinct results.

The normal149 installed baseline executes one test with zero failures and
requests all13 original CJ files through the existing resource APIs. Reviewed
captures show a white CJ silhouette while the surrounding original world and
objects are textured. Resource metadata and native preferences remain retained;
no install/reset was used for this baseline. The current SDK products and
identical normal150 case remain pending.

## Completed SDK and normal installed-game acceptance

The earlier pending gates subsequently pass: universal Simulator Debug501.3
seconds and iPhone arm64 Release501.2 seconds. Both products hold all227
App/build inputs,39 independent library dependency records and14 self-contained
owner-menu files. No original resources are included in the public source.

The identical normal150 UI case executes one test with zero failures in152.3
seconds of runner time. Its first launch was rejected by Apple before any test
ran (zero tests, exit65,67.2 seconds); that separate result is retained. The
unchanged retry joins and spawns CJ, walks/orbits/pauses, performs two
jump/land/walk transitions and returns through the normal installed-resource
menu. All13 original CJ files are requested, their hashes remain held, the exact
five installed app payloads match the compiled product, and prepared/raw
metadata and native preferences remain retained. A normal update can move the
app's data-container directory; equality was checked by retained content, not
by assuming an unchanged container path.

Reviewed before/after captures show the original skin, vest, denim and shoes
replacing the white baseline silhouette, including after the jump/land/walk
case. This verifies this visible material repair, not original movement timing
or exhaustive character/retail fidelity. The app, dedicated Simulator, owned
loopback resource proxy and capped QA server are stopped after acceptance.
Physical-device performance, scene fog/timecycle, ordinary raw-family game
registration, canonical gaps and all other unmeasured gameplay remain open.
