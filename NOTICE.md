# Source and local content

ZGTA:SA project contributions are distributed under the GNU Affero General
Public License version 3 only (SPDX: AGPL-3.0-only). Copyright 2026 ZGTA:SA
contributors. The full license is in LICENSE. This grant applies to the project
contributions; third-party dependencies retain their own licenses.

The source release does not include the original website's downloaded bundles,
San Andreas game data, converted derivatives, music, publisher accounts or
private multiplayer backend. The archive and converters write content under
the ignored local-only directory. This project's license grants no rights to
that separate content. GTA and San Andreas names belong to their owners.

The native physics bridge builds upstream Rapier and glam dependencies pinned
by native-physics/Cargo.toml and Cargo.lock. Their upstream notices and license
terms continue to apply. The Python conversion dependencies are declared in
requirements-native.txt and retain their own licenses. Native build outputs
and downloaded dependency/toolchain copies are kept outside this source release.

The independent server is a separate implementation. Original browser-client
behavior is used as a local reference for native translations and numerical
comparisons. Public asset tools depend on the archived client version; they
do not include or reconstruct private server source. Coverage and open work
are tracked in FEATURE_MATRIX.md.
