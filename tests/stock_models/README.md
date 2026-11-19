`tools/assets/prepare_native_stock_models.py` generates owner-local stock model metadata from
an owned game data tree and a read-only raw DFF/TXD directory. It follows only
active IDE declarations from `data/default.dat` and `data/gta.dat`; an explicit
`--extra-ide` can add a separately supplied SA-MP supplemental definition file.
Commas and whitespace are parsed as the original loaders do. Model ID, exact DFF
stem, TXD name, source row and explicit parent relationships are retained. Unknown
IDs, missing files and parent cycles are never replaced with a similar model.

Generated metadata and all reference files must remain under `local-only`. Example:

```
python3 tools/assets/prepare_native_stock_models.py \
  --game-root local-only/research/stock-models/retail-ide \
  --asset-root local-only/site/game \
  --output local-only/original-world-assets/game/native/stock-models.json
```

The default URL prefix is `game`. `NativeSAMPStockModels.decode(Data)` loads the
bounded manifest; `resolve(id:assetBaseURL:)` returns model metadata, optional DFF,
the complete named child/parent TXD chain, and explicit missing filenames.
`dictionary(named:assetBaseURL:)` resolves exact material dictionary names. Supply
the asset origin/root containing `game/`, rather than an already suffixed `/game/`
URL. File URLs can exercise the same lookup locally. Each actual asset carries
byte count, CRC32 and SHA-256 for a later downloader/importer to verify.

Availability is not importer/render acceptance. In particular, a present DFF may
require skinning, vehicle part rules, animations or unsupported plugins. The
helper does not fetch assets, merge textures or modify Renderer/GVC. Callers must
load and verify each asset, merge texture dictionaries in the returned search
order, and perform real import/upload before marking an object available.

Vehicles have an explicitly identified generic `vehicle` parent, supported by
[CFileLoader::LoadVehicleObject](https://github.com/gta-reversed/gta-reversed/blob/master/source/game_sa/FileLoader.cpp),
file blob SHA `a575e2b0625addd1d2b75e72e710efd4f5f303d5`, checked 2026-11-16.
[CVehicleModelInfo::FindTextureCB](https://github.com/gta-reversed/gta-reversed/blob/master/source/game_sa/Models/VehicleModelInfo.cpp),
blob SHA `56181bad17f7bb7bb63cf28ea6b18b97db0102e2`, supports searching that generic
dictionary before vehicle-local textures. The generator records this supporting
engine rule separately from IDE-declared parents. No reconstruction code or
original reference rows are embedded in the independently written source.

The local reference investigation selected only 61 IDE/config members totaling
696,851 bytes using the already pinned, hash-verified MIT Unshield tool. No game
installer or executable was launched. No whole-world conversion occurred. CAB
inventory separately identifies retail `gta3.img` at 940,064,768 bytes and
`gta_int.img` at 150,024,192 bytes; extraction/indexing is separate work.

The initial browser corpus supplies 584 DFFs and 547 TXDs: it covers many actors,
vehicles and weapons but almost no retail map props. Common map object definitions
exist in the selected IDEs while their raw DFFs are missing from that corpus.
SA-MP-added objects such as 19379/19353/19480 are absent from retail GTA metadata
and require their actual supplemental definitions/assets. Merged browser world
tiles are not substituted for those exact standalone objects.

Run `python3 tests/network/test_samp_stock_models.py`. Generated cases check active-file loading,
mixed separators, exact paths, parent/generic ordering, missing files, cycles,
malformed metadata, traversal and size limits. Owner-local cases resolve actual
weapon/vehicle files and verify their size and SHA-256. Reports and source hashes
remain under `local-only/research/stock-models`; original data/assets stay local.
