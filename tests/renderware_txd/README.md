Run `python3 test_native_renderware_txd.py` from the repository root. The default
run checks the owner-local `local-only/site/game/*.txd` corpus as well as generated
fixtures. Use `--no-corpus` for the generated tests alone. Swift, CryptoKit (test
hashing only), Python, and Pillow must be available. No network requests occur.

All manifests, generated fixtures, build products, hashes, and reports are placed
under `local-only/research/renderware-txd`; original archives are opened read-only
and their hashes checked again after testing. No original image data is embedded
in these tests. `prepare_native_models.py` is imported only to cross-check its
existing base-mip converter; its CLI and output-generation functions are not run.

The production reader returns CPU images; it does not create Metal textures or
render custom models. It supports D3D9 DXT1/3/5, A8R8G8B8, X8R8G8B8, R5G6B5,
X1R5G5B5, A1R5G5B5, A4R4G4B4, X4R4G4B4, L8 and A8. Palettes, cube maps, other
platforms, unknown pixel formats, and non-ASCII/path names are explicitly rejected.
Default limits are 64 MiB encoded, 128 MiB decoded RGBA, 2,048 textures, 4,096 per
dimension, 13 mip levels, and 16,384 parsed chunk headers. Trusted callers may
override these budgets.

Stored mip levels have tightly packed, top-down, straight-alpha RGBA8 pixels.
Empty trailing BC mip records below 4×4 remain `rgba8 == nil`; callers must choose
an appropriate resident mip range or explicitly generate replacements. The reader
does not silently synthesize missing original data. X color bits are ignored and
output alpha is 255. BC integer expansion/interpolation matches Pillow's BC
decoder; raw RGB565 matches Pillow's raw decoder. GPU implementations may differ
by one unit in interpolated/expanded color rounding. These tests do not establish
GPU or original-game rendering parity.

Format references checked on 2026-11-16:

- [librw's MIT-licensed D3D9 native-texture reader](https://github.com/aap/librw/blob/master/src/d3d/d3d9.cpp), file blob SHA `851397b675257b47ff1667d3125d966ba803c952`, confirms stream fields, palette placement and mip record boundaries. No library code is included or linked.
- [Microsoft block compression](https://learn.microsoft.com/en-us/windows/win32/direct3d10/d3d10-graphics-programming-guide-resources-block-compression), [BC1](https://learn.microsoft.com/en-us/windows/win32/direct3d9/opaque-and-1-bit-alpha-textures), and [BC2/BC3 alpha](https://learn.microsoft.com/en-us/windows/win32/direct3d9/textures-with-alpha-channels) describe block packing and alpha modes.
- [Microsoft D3DFORMAT](https://learn.microsoft.com/en-us/windows/win32/direct3d9/d3dformat) defines raw channel layouts and unused X bits.

The generated corpus covers reversed/equal BC endpoints, BC1 transparency,
BC2 explicit alpha, both BC3 alpha branches, clipped blocks, exhaustive 16-bit raw
words, X-bit alpha behavior, mip chains, empty tiny tails, case-insensitive name
collisions, truncation at every byte of a valid file, malformed lengths/counts,
unsupported formats, and each resource budget. Every stored output mip is checked
byte-for-byte through an RGBA SHA-256 hash, with dimensions and native metadata.
