# Owner menu import

The native menu can load images, fonts and sounds from your own compatible
San Andreas Definitive Edition iOS IPA. The public source includes the importer,
format readers and independent codec wrapper. Original resources and compiled
codec/cache files remain under ignored `local-only/`.

From a fresh source checkout, run:

```sh
python3 tools/assets/import_de_menu.py --ipa "/path/to/your-game.ipa" --output local-only/menu-bundle/OwnerMenu
```

`--ipa` and `--output` are required. Output must be a **new directory** beneath
this checkout's `local-only/`. Existing owner resources are never overwritten.
For another import, select a new output folder. A failed import removes its
temporary staging directory and does not publish a partial manifest.

Build with `zsh build_native.sh simulator` or `zsh build_native.sh device` after
import. The wrapper adds the local folder only when its `manifest.json` exists,
by selecting `ios/project-owner-menu.yml`. A checkout without that manifest uses
the source-only `ios/project.yml`, which has no owner-resource reference. If
generating a project manually from the `ios` directory, explicitly use
`xcodegen generate --spec project-owner-menu.yml` after import, or
`xcodegen generate --spec project.yml` for the source-only fallback. The owner
spec requires its folder; it does not rely on optional missing paths.

The IPA remains a data source. The importer does not install the app, read or run
its executable, load game libraries, request encryption keys or decrypt data.
Encrypted indexes/resources and unsupported package variants fail with a reason.

## Independent decompressor

Oodle-compressed resources need the small independent `zgta-menu-codec` helper.
On its first use, the importer builds only `native-menu-codec/Cargo.toml`, with
`--locked --release`, using an existing Cargo/Rust installation. It never
installs Rust or changes a shell profile. Its Cargo registry and target caches
default to `local-only/menu-import-codec/`. Later imports reuse a binary whose
source and binary hashes match the local build record.

If Cargo is outside `PATH`, supply its existing executable:

```sh
python3 tools/assets/import_de_menu.py --ipa "/path/to/your-game.ipa" --output local-only/menu-bundle/OwnerMenu --cargo "/path/to/toolchain/bin/cargo"
```

`--cargo-home /path/to/private/cargo-cache --offline` reuses an available registry
cache without fetching dependencies. A fresh build otherwise needs the locked
registry dependencies. No native physics libraries are built or changed.

An already-built independent decoder can be selected explicitly:

```sh
python3 tools/assets/import_de_menu.py --ipa "/path/to/your-game.ipa" --output local-only/menu-bundle/OwnerMenu --decoder "/path/to/zgta-menu-codec"
```

Its interface is `INPUT OUTPUT EXACT_OUTPUT_BYTES`; failure or a different output
size aborts import. Use an independent helper you trust. The report records its
binary SHA256; a caller-provided helper is not labelled as the pinned build.
`--no-build-codec` prevents an automatic build and gives a clear error when the
required helper is unavailable.

The included wrapper pins `oozextract =0.5.7` and commits a checksummed dependency
lock. The project's [primary package metadata](https://github.com/lvlvllvlvllvlvl/oozextract/blob/master/Cargo.toml)
declares version 0.5.7 and MIT licensing. The importer never uses the game's codec
binary. Python uses only its standard library; Pillow, Unreal tools and FFmpeg
are not needed.

## Selected output and integrity gates

Only `pakchunk0-ios.pak` and its `pakchunk1-ios.pak` patch index are inspected.
Their different mount points resolve to the same virtual content namespace;
the patch wins before payload extraction. The importer selects 18 resource
entries that produce these files:

| Manifest role | Resource |
| --- | --- |
| `images.logo` | DE San Andreas logo |
| `images.background` | San Andreas menu background |
| `images.portrait` | San Andreas menu portrait |
| `images.selectedPlay` | Resume selected background |
| `images.selectedGame` | Game selected background |
| `images.selectedOptions` | Options selected background |
| `fonts.menu` | PRICEDOWN face, PostScript `PricedownGTAVInt` |
| `fonts.body` | Arial Bold face, PostScript `Arial-BoldMT` |
| `sounds.start/back/highlight/tab` | Frontend S000 / S004 / S009 / S006 |

Six PNGs preserve the source BGRA texture pixels and alpha through lossless RGBA
conversion. SFNT font bytes are unchanged; their signature determines `.ttf` or
`.otf`. Microsoft ADPCM WAV bytes are unchanged; native audio prepares them at
runtime. The importer adds `manifest.json` and `import-report.json`.

The reader checks primary, path-hash and directory-index SHA1 values, physical
entry/index agreement, selected compressed-payload SHA1, every decompressed
block length and total decoded size. Texture mip dimensions/bulk offsets, font
table ranges/PostScript names and WAV format/block lengths must also agree.
Hashes check consistency with the archive; they do not authenticate its publisher.
The report records the IPA SHA256, index locations, selected resource provenance,
decoder hash and output/pixel hashes.

Limits are explicit: Pak v11, unencrypted indexes and selected entries, up to
2 GiB per selected Pak, a 32-MiB index tail, 100000 directory entries, 8 MiB per
selected resource and 32 MiB total selected output. The texture profile supports
one inline BGRA8 mip up to 2048 × 2048. Other texture/codec/layout variants fail
instead of being guessed.

The supplied IPA stores its Paks inside deflated ZIP members. Reaching a Pak
index therefore requires streaming and discarding preceding uncompressed Pak
bytes. No full IPA directory tree or whole Pak is written or retained. Other
Pak chunks, game executables, missions and world resources are not selected.

## Reproducible checks

Synthetic tests require no original data, network or Rust toolchain:

```sh
python3 tests/hosting/smoke_de_menu_import.py
```

They cover patch overrides, exact transparent pixels and font/WAV copying,
stored/Zlib payloads, corrupt index and payload hashes, header/size mismatches,
encryption/version rejection, missing resources, unsafe output/virtual paths,
failed staging cleanup, truncated resources and unavailable/incorrect codecs.

An optional owner-data check runs the same import:

```sh
python3 tests/hosting/smoke_de_menu_import.py --ipa "/path/to/your-game.ipa" --output local-only/menu-import-test/OwnerMenu
```

`--reference /path/to/private/de-menu-assets` additionally compares six PNG/pixel,
two font and four WAV hashes against the retained independent resource reports.
That comparison is optional and distinctly skipped when absent. No test depends
on a private research path in a fresh checkout. Only source and synthetic fixture
builders belong in Git; never add the IPA, extracted outputs or codec binaries.

This reconstructs the observed static menu resources. It does not establish
runtime Blueprint/native menu behavior, original story-mode integration or game
engine compatibility.
