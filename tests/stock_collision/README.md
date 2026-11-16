# Exact stock collision association

`prepare_native_stock_collision.py` independently reads PC `VER2` IMG directories
and bounded COL record headers. Inputs are an owned stock IDE manifest, its exact
IMG archives and optional explicit COLFILEs. Outputs stay under `local-only`; no
original geometry, model-name catalog, fixture or oracle is public source.

```sh
python3 prepare_native_stock_collision.py \
  --img /path/to/owned/models/gta3.img \
  --img /path/to/owned/models/gta_int.img \
  --stock-models local-only/stock-models.json \
  --output local-only/stock-overlay/game/native/stock-collision
```

`--model exact_ide_name` narrows export; omitting it includes every name with
explicit owner IDE provenance. To establish complete inventory for that exact
stock manifest, also supply `--stock-index` (the matching virtual IMG asset index),
`--game-root` (the matching IDE/config tree) and each active explicit file using
`--col models/coll/weapons.col=/path/to/owned/weapons.col`. The generator verifies
archive sizes and directory hashes against the stock index, config hashes against
the stock manifest, and complete active COLFILE coverage. An incomplete inventory
can export genuine records but cannot classify a missing record as noncolliding.

Schema 2 separates owner IDE bindings (ID, exact name, source row and source SHA)
from the original COL header ID. The header ID is a lookup hint: native preparation
checks it against the hashed record metadata, rather than requiring equality to
the requested IDE ID. Identical raw records have explicit aliases; different
same-name records remain ambiguous. Unknown names or mismatched IDE provenance
never resolve through a nearby or similarly named object.

This follows the community primary reconstruction
[CFileLoader::LoadCollisionFile/FirstTime](https://github.com/gta-reversed/gta-reversed/blob/master/source/game_sa/FileLoader.cpp),
blob `a575e2b0625addd1d2b75e72e710efd4f5f303d5`: numeric lookup is checked against
the name key and falls back to name lookup; the filename overload uses the name.
[CColStore](https://github.com/gta-reversed/gta-reversed/blob/master/source/game_sa/Collision/ColStore.cpp),
blob `4540ee8ef46aaf2f13603725a5b5b824fd31bae6`, delegates these loaders. No reference
implementation is copied, imported or linked; retained reference artifacts remain
private. The repository's inspected root contains no LICENSE file, so this is
behavioral evidence rather than authorization to redistribute its implementation.

No-COL rendering is a separate explicit classification. A complete inventory is
bound to the exact stock manifest SHA-256. Only a known owner IDE binding with no
matching authored record, the matching manifest digest and complete inventory can
return `noAuthoredCollision`. Embedded DFF collision is still checked separately.
Missing metadata and failed record integrity remain unavailable. No synthetic box
or visual-mesh collider is created. Supporting reconstruction references are
[CBaseModelInfo::Init](https://github.com/gta-reversed/gta-reversed/blob/master/source/game_sa/Models/BaseModelInfo.cpp)
(blob `b9130a59447009672fff3cf161dddef6f3790d5f`, initial COL pointer is nil),
[CAtomicModelInfo::CreateInstance](https://github.com/gta-reversed/gta-reversed/blob/master/source/game_sa/Models/AtomicModelInfo.cpp)
(blob `55aad44621d587d59ab62299639dd588e645f5f8`, visual cloning is independent of COL),
and [CEntity::CreateRwObject](https://github.com/gta-reversed/gta-reversed/blob/master/source/game_sa/Entity/Entity.cpp)
(blob `8a4c48658e120ceed8f251c3c9a3115572ff0c58`). This does not establish every
activity-specific fallback or inherited timed-model collision relationship.

`NativeSAMPStockCollisionCatalog.decode` validates bounded metadata;
`resolve(modelID:modelName:source:line:stockManifestSHA256:assetBaseURL:allowLocalFiles:)`
returns missing, unique, ambiguous or verified inventory absence. A unique `File`
exposes path, bytes, CRC32, SHA-256, source aliases and URL. Acquire it using bounded
I/O, then call `catalog.prepare(_:for:)`. Preparation rechecks size, both hashes,
name, raw header hint and version before returning one authored COL model.

```sh
python3 smoke_native_stock_collision.py
python3 smoke_native_stock_collision.py \
  --owner-catalog local-only/stock-overlay/game/native/stock-collision/catalog.json \
  --owner-overlay local-only/stock-overlay \
  --oracle-root local-only/research/runtime-collision
```

Generated tests cover container bounds, unsupported compression, record bounds,
provenance/identity, ID hints, missing/ambiguous names, aliases, resource limits,
CRC/SHA, incomplete versus complete absence, URL validation and truncated data.
Real Rapier checks use authored volumes, full three-axis poses, material/piece tags,
movement and cleanup. Shadow geometry never becomes physical. The optional
unmodified DragonFF oracle and its GPL license stay private and are not shipped.
Header inventory, geometry decoding, renderer acceptance and actual game-session
acceptance remain separate coverage claims.
