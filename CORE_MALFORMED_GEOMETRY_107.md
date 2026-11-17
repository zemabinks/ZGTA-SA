# Malformed geometry handling — Core107

An actual owner-resource inventory found eight nonfinite UV components across three prepared vehicle files: Buccaneer's base and rig meshes, and Petrol Trailer's rig mesh. The inspected base/rig families for Caddy were finite. Positions in the inspected 735 indexed/bootstrap meshes were finite. Original bit patterns and derived-file hashes remain in private evidence.

`WorldBinary` now rejects nonfinite positions and maps each nonfinite UV component to zero before Metal upload. It exposes `repairedUVComponents` for diagnostics. Finite positions, finite UV components, indices and material/layer assignments are preserved. All meshes follow this rule; no model filename is exempted.

Zero is a deterministic fallback for malformed source data. It does not reconstruct the unknown intended original UV or establish exact original texture appearance. Conflicting UV seams prevent a justified nearest-vertex repair. Native resource verification remains strict about the decoded geometry's finite coordinates.

Regression coverage uses all six actual Buccaneer/Caddy/Petrol Trailer base/rig families, exact repair counts, finite-value bit preservation, unchanged triangle indices and NaN/positive-infinity/negative-infinity position rejection. The full Renderer actor-family retry carrier also passed with the updated decoder. These checks establish decoding and loading behavior, not a new rendered gameplay or retail-parity result.
