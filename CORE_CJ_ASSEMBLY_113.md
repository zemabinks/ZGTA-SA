# Fixed Normal CJ assembly

This document records Core113's initial bounded preparation phase for the segmented player body. It assembles actual owner-provided clothing geometry, textures and the player rig; it does not substitute an ordinary pedestrian for CJ. The initial phase did not register skin0. The subsequent explicit fixed-profile acquisition and runtime source are documented in [CORE_CJ_RUNTIME_113.md](CORE_CJ_RUNTIME_113.md). Its available vest/denim/sneaker descriptor has not been authenticated as the original initial multiplayer wardrobe.

## Implementation

- `NativeCJAssembly` selects the third, explicitly named **Normal** clump from each Ripped/Fat/Normal clothing stream. The normal DFF decoder remains unchanged. Only bounded, all-zero IMG allocation tails are accepted.
- All five components join the actual player template by HAnim bone ID. The template owns the final inverse binds and animation palette. Positive weights referencing missing bones fail; unused garment bones are reported. Source positions, weights, UVs and topology are preserved, with one floor/axis correction for the completed body.
- `NativeCJTextures` resolves explicit dictionary/texture identities and preserves dimensions, sampler settings and available mips. A clothing cut copies the whole source texel when its alpha is nonzero; it does not use ordinary alpha blending. Missing, ambiguous, incompatible or oversized inputs fail.
- `NativeCJClothesRules` conservatively admits a fixed Normal descriptor. It validates the owner rule grammar and rejects descriptors requiring normal model/texture/hide resolution. It does not guess unreversed IGNORE/EXCLUSIVE precedence or apply cutscene-only CUTS to the normal body.
- `NativeCJResources.prepare` bounds and hashes the complete input recipe. `NativeRenderWarePedModel.prepareCJ` then uses the existing material resolver, SKN1 contract, skeletal actor and Metal pipeline. Acquisition, source trust and runtime skin admission remain the caller's responsibility.

The five source modules are independent of networking and UIKit. Existing DFF/TXD/skeleton/actor/model implementations, Renderer, GVC and the skin catalogue are unchanged by this work.

## Evidence

The public CPU test uses authored data and has no owner-asset activation mode. Separate private owner carriers check the previously selected local pieces against their preserved extraction hashes and independent per-vertex/Pillow texture oracles. The public source contains no game files, derived pixel/geometry goldens or owner-executing test code.

| Check | Observed result | Boundary |
| --- | --- | --- |
| Public authored parser, assembly, textures, rules and malformed inputs | 63 checks PASS | No original assets required |
| Private CPU owner pass, including the same authored checks | 22,908 checks PASS | Fixed candidate, not retail gameplay |
| Owner mesh | 1,721 source vertices, 2,332 triangles, 32 template bones | No full wardrobe or body morphing |
| Shared seams | 56 coincident pairs; rest error ≤1.23e-7 m | No coincident jeans/shoe ankle pair exists |
| Actual existing CLP/actor path | 18 poses from idle, walk, run, crouch, swim and car-sit clips | Clip playback, not controller or seating acceptance |
| Actual desktop Metal upload/draw/readback | 1,069 checks PASS, six material draws per frame | Offscreen AMD GPU; no iPhone/app acceptance |
| Animated coincident seams | Maximum error 2.39e-7 m | Not matched to original-game footage |
| arm64 iOS15 SDK typecheck | PASS, 17 unchanged relevant modules | Typecheck only; no app build or device run |

All sources and owner input hashes were unchanged during the accepted CPU and GPU runs. Earlier failed attempts are retained privately: a concurrent-edit typecheck, the real clothes.dat CRLF parsing failure, and test-only GPU Swift compilation errors. The CRLF case now has an authored regression.

Run the asset-free CPU suite with:

```sh
python3 smoke_native_cj_assembly.py
```

Private owner validation requires the separately owned local selection. GPU validation also requires the existing shared animation library and a functioning Metal device; successful CPU parsing alone does not imply rendering. Exact private carrier originals and their accepted report hashes are retained independently of the public authored suite.

## Remaining runtime boundary

The selected body uses `vest`, `head`, `hands`, `jeans` and `sneaker` Normal geometry. Its explicit full-resolution texture recipe is player torso plus vest cut, player face, denim legs and the matching sneaker texture. The template is the tiny rig in `player.dff`, which is not a complete character on its own. Similarly named standalone dictionaries are not automatically merged.

Before enabling skin0, the app still needs:

1. An authenticated fixed descriptor/default-profile decision. The supplied pieces establish an available coherent body, not the original server's initial wardrobe, body stats, haircut or retail silhouette.
2. A bounded trusted provider for the template, five component DFFs, five exact TXDs and clothes rules, through installed raw resources or an explicit prepared manifest. The existing shared CLP library and PLAYER1 animation metadata must also be present.
3. Atomic, generation-fenced GPU registration for the composite model, including the original style-table name `null`/PLAYER1. Falling through to an ordinary-ped style is not accepted.
4. Actual local and remote skin0 scene tests, reconnect/cancellation and installed/offline admission checks, followed by original-game visual and movement comparison.

Ankle overlap, initial wardrobe, fat/muscle blending, wardrobe changes, tattoos, complete cutscene clothing and original animation timing remain unverified. Inspection angles in the offscreen test are test cameras. This is not full CJ, gameplay or 1:1 retail parity.

## Provenance

The implementation is independently authored under AGPL-3.0-only. It uses the existing independently authored RenderWare and skeletal substrate. Owner assets, parsed reference data, animation libraries and readbacks remain private local files.

The preserved owner assessment supplies the actual clump order, palette identities, source joins and available texture dimensions. The community reconstruction of [ClothesBuilder.cpp](https://github.com/gta-reversed/gta-reversed/blob/master/source/game_sa/ClothesBuilder.cpp) and [Clothes.cpp](https://github.com/gta-reversed/gta-reversed/blob/master/source/game_sa/Clothes.cpp) supports template-palette joining and nonzero-alpha texel replacement. No implementation was copied. Its central texture/geometry construction functions still defer to unreversed original functions, so it cannot certify the complete wardrobe algorithm. No new REA Evidence IDs were generated because REA tooling was unavailable in this session.
