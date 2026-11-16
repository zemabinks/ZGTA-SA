`NativeSAMPObjectMaterials` resolves parsed object material values into native
textures and per-draw overrides. It does not modify application Renderer/GVC code.

Construct `Owner(device:limits:textureResolver:fontResolver:)`, then pass the value
from an object's material slot to `resolve(_:)`. Apply the result to that draw's
`NativeRenderWareModel.DrawOverrides` using `resolved.apply(to: &overrides)`.
The injected texture resolver receives the signed wire16 model ID and the exact
dictionary/texture strings. It must return resources from the same Metal device.
There is no global-name fallback or matching to an unrelated dictionary.
Missing textures and unavailable font faces fail explicitly, so the caller can
keep the original material and report the unresolved value.

The optional static-model overrides replace texture, sampler, material color and
blend state. Nonzero material tint also disables baked vertex color, as documented
by the server API. A single shader flag supports this; its default is zero and
existing rendering remains unchanged. Other transforms, tint and lighting remain
under the caller's control. The existing shader uniform layout remains 240 bytes.

Material texture tint is ABGR **on the wire**. Text foreground/background remain
ARGB. A zero texture tint inherits the old material color. Model -1 performs a
color-only change; model0 uses an untextured white source for the documented alpha
case. Named texture requests preserve original dictionary/texture identity. Text
materials replace the source material color with white and disable old baked
vertex color. Callers may override blend state when their scene requires it.

Text uses native CoreText/CoreGraphics, with all fourteen published texture sizes,
left/center/right alignment, word wrapping, explicit newlines, font size and bold,
transparent backgrounds, and `{RRGGBB}` embedding. Embedding preserves the requested
font alpha. The color space is explicitly sRGB; device RGB color management would
shift some protocol color values. Premultiplied CoreGraphics pixels are converted
to tightly packed, top-down, straight-alpha RGBA8 before Metal upload. Text never
uses UIKit screen scaling or resizes into an atlas. Clipping is exposed in the
resolved result.

The default font resolver accepts an installed family, full or PostScript name
and resolves a real bold face when requested. It never silently substitutes an
unavailable font. A caller can inject a resolver for separately licensed local
fonts. CoreText's metrics/kerning/rasterization may differ from the original
Windows font engine; these tests do not establish identical original glyphs.
Published color/dimension/alignment behavior and actual native output are tested.

The image LRU is bounded by retained RGBA texel bytes and entry count; the font LRU
has a separate count limit. Unknown external texture pixel formats are rejected,
and only ordinary 2D RGBA/BGRA8 textures are admitted. Text length, font/name length,
dimensions and configurations are bounded. `reset()` releases cache references;
invoke it when switching servers or replacing a catalog. Do not retain cache
results indefinitely outside the owner's budgets without another memory policy.

Primary references checked on 2026-11-16:

- [Official object RPC source](https://github.com/openmultiplayer/open.mp/blob/72bf89ce4c8164f7f7b8271ffc7323bc45ea005f/Shared/NetCode/object.hpp) confirms texture `ABGR()` and text `ARGB()` serialization.
- [SetObjectMaterial](https://open.mp/docs/scripting/functions/SetObjectMaterial) specifies color0 inheritance, model -1 and0 semantics, and removal of vertex lighting when the color changes.
- [SetObjectMaterialText](https://open.mp/docs/scripting/functions/SetObjectMaterialText), [sizes](https://open.mp/docs/scripting/resources/materialtextsizes), and [alignments](https://open.mp/docs/scripting/resources/textalignments) specify text parameters and embedding.

Run `python3 test_samp_object_materials.py` with access to the native Metal device.
It checks native font/image behavior, exact background/alpha channels and all
published dimensions; reads uploaded text pixels; checks exact lookup and cache
budgets; then renders real offscreen draws to verify texture/sampler/color/prelit
and blend replacement. It also confirms default source color/prelit behavior.
Reports and the reviewed native text preview remain local-only under
`local-only/research/object-materials`. No original game assets are included.
