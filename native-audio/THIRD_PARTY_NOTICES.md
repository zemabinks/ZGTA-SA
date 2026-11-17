# Codec notices

The following unchanged components use the Xiph BSD3 license. The full notices,
conditions and disclaimer are retained in these source files and must also be
included in distributed App third-party notices/materials when linked:

- `vendor/libogg-1.3.6/COPYING`
- `vendor/libvorbis-1.3.7/COPYING`

Exact upstream release URLs, archive SHA-256 hashes and the retained per-file
SHA-256 inventory are in `vendor/provenance.json`. Selection excludes encoder
library/tools/autotools artifacts. No original game implementation or game audio
is included. These software licenses grant no rights to original recordings.

Compilation backports Xiph's BSD-licensed
[unsigned codebook-prefix shift fix](https://github.com/xiph/vorbis/commit/bb4047de4c05712bf1fd49b9584c360b8e4e0adf)
by Tristan Matthews. The exact one-line transform is hash-pinned in `patches/`
and applied only to private compiler output; the upstream release files and
complete license notices remain unchanged.

Our independent adapter, allocation prefix, Swift catalogue/substream, build and
portable regression sources are AGPL-3.0-only, as marked in those source files.
