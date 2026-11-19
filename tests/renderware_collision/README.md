# Authored RenderWare/GTA collision regression

Run `python3 tests/resources/smoke_native_renderware_collision.py` on the owner development Mac,
or add `--no-archive` to run only original generated inputs. Outputs, owner
collision data and optional third-party reference files stay beneath ignored
`local-only/research/runtime-collision`. No exporter or original script runs.

`NativeRenderWareCollision.decode(Data)` reads headered COLL/COL2/COL3 collections.
`decodeHeaderlessCOL1(Data)` explicitly reads legacy data without inventing a
model name or ID. `embedded(inDFF: Data)` locates clump plugin `0x253F2FA`, retaining
its source offset and stream size. The known plugin context permits genuine
headerless legacy data; an unknown ordinary COL file signature fails explicitly.
A DFF with no collision plugin returns no collision. There is no visual-mesh or
generic bounding-box substitution.

All output coordinates retain authored GTA Z-up units. Main physical spheres,
boxes and indexed triangles remain separate from `shadowMesh`. Primitive surfaces
retain material, piece/flags, brightness and packed day/night lighting bytes.
COL2/3 mesh faces do not store the legacy flag/brightness bytes; those fields are
explicitly absent. Authored bounds and optional face groups remain available.
The caller supplies model placement and physics integration separately.

The decoder bounds files, models, chunks, shapes, vertices, faces and aggregate
resource use. It validates lengths, section ranges/overlap, offsets, indices,
finite floats, ordered boxes, nonnegative radii, face groups and shape/shadow
flags. Nested DFF chunks remain strict; only bounded final IMG sector zero
padding is accepted. Suspension/cone primitives, stored triangle-plane arrays
and COL4 are explicitly unsupported. No such unsupported payload occurred in
the actual owner collision corpus.

The primary format reference is Parik's
[DragonFF gtaLib/col.py](https://github.com/Parik27/DragonFF/blob/master/gtaLib/col.py).
Its header identifies Copyright (C) 2019 Parik, GPL-3.0-or-later; the repository
[license](https://github.com/Parik27/DragonFF/blob/master/LICENSE) was reviewed.
The application decoder and generated fixture writer are independently written;
no DragonFF implementation is copied into or linked by the application. For this
development comparison the exact original reader and license were retained only
in the ignored research reference directory. Reader SHA256:
`aba846b000507b11107e93c711e199b3867cccc466d1c363874cb0886ef23c3f`.
The optional oracle reads valid fixtures/owner streams only, with its name-length
dependency supplied independently; malformed inputs never reach that unbounded
reference reader. Without that private reference, reports explicitly identify
the weaker owner-corpus validation.

Actual coverage: all 584 owner DFFs inspected; 211 COL3 payloads and rccam's one
headerless COLL payload compared field-for-field against the primary reader.
These contain 5,419 spheres, 12 boxes and 2,666 physical faces. The separately
preserved shadow meshes contain 81,404 faces and are never physical faces.
Headered COLL and COL2, nonempty face groups and assorted malformed inputs have
generated-input coverage; no executable retail COL2 comparison is claimed.
The complete suite has 1,296 cases and passes arm64 iOS 15 SDK typechecking.
This verifies authored collision decoding, not a Rapier bridge or gameplay parity.
