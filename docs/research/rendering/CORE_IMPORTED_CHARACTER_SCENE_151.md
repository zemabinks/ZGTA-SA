# Imported-character scene fog (151)

The existing CJ/custom-pedestrian draw path supplied material, opacity and pose
but omitted the environment configured for ordinary actors. Its fragment had no
depth or fog input. Thus acquiring the original textures alone could not make a
remote imported character obey the same scene visibility as nearby actors.

The skinned vertex stage now carries clip-W depth. A separate pedestrian
fragment shares the static renderer's existing material operation, then applies
the ordinary actor's linear distance fog to RGB. Material cutoff occurs first;
opacity, blending and depth-write ownership remain material decisions. Each
pedestrian draw binds its own scene, including a disabled default for previews
and verification. The common static uniform layout and static-object fragment
interface remain unchanged.

The actual world draw passes the environment it already configures for that
actor: exterior fog, reduced atmospheric amount, lightning fog color and the
disabled interior/default case. This changes neither movement nor networking.
It does not supply missing original pedestrian timecycle/directional lighting.

## Validation gates

The focused fixture uses the production rig decoder, actor, encoder and Metal
shaders with authored resources. An independent pixel oracle checks clip-W
distance, start/end saturation, partial/disabled atmosphere, collapsed/reversed
intervals, lighting/tint order, alpha cutoff, alpha blending and multiple scene
owners in one render encoder. A historical mode uses the actual150 source and
shaders unchanged; its test adapter only binds the scene to an otherwise unused
fragment slot. The actual150 encoder/shaders fail the intended half-fog pixel assertion.
Current151 passes5424 scene/pixel checks,32 actual skinned draws in14 Metal
passes, including same-encoder default-scene isolation and nonfinite rejection.
The existing material gate remains70 checks/28 static/skinned renders. The
three owner-local original-family resource/GPU-byte gate passes221 checks.
The full selected Metal/physics/audio/transport chain passes in854.5
seconds, with all227 App/build inputs and three captured test sources held;
project, hosting and layout pass. Both SDK products and the normal installed-app
case subsequently pass; details and limitations follow below. Physical-device and original-retail acceptance are separate.

This is a correction to our existing native environment contract, not proof of
original GTA SA rendering parity. Ordinary raw-family game registration,
canonical resource gaps, world purple surfaces, timecycle lighting, ambient
simulation and all other unmeasured gameplay differences remain open. Original
resources, generated images and captures remain local.

## Completed SDK and normal installed-app acceptance

The universal Simulator Debug build passes470.7s and the iPhone arm64 Release
build492.7s. All227 App/build inputs,39 independent dependency records and14
self-contained private owner-menu files remain held. These are unsigned SDK
products, not a physical-phone performance result.

The ordinary installed151 update retains the exact compiled payload, prepared/
raw metadata and native preferences. The unchanged join/spawn/walk/camera/
pause/two-jump-and-land/installed-mode case executes one test with zero
failures in150.0s of runner time. A separate Apple preflight rejection executes
zero tests (exit65,68.5s); its receipt is retained. All13 original CJ files are
requested and held. Reviewed captures retain the textured character, world
objects, Taxi, HUD and controls, including after the jump/land/walk sequence
and normal installed-menu return.

This near-character scene does not numerically measure distant fog. The actual
Metal pixel oracle establishes the stated fog formula and state isolation;
the normal case establishes ordinary app integration and retained data. Neither
establishes original-PC fog, lighting, controls or gameplay1:1. The app, dedicated
Simulator, owned loopback proxy and capped server are stopped after acceptance.
Original files, derived assets, captures and private histories remain local.
