# Persistent native resources — Core107

The app now separates its source build from resource preparation. Native asset reads use a shared resolver; HTTP gameplay, authentication and WebSocket traffic continue to use their normal connections. This is a prepared-resource foundation, not a complete original-game port or a complete ISO-to-native installer.

## Development and installed modes

`python3 prepare_native_resource_package.py` indexes an already prepared Mac runtime. It does not extract an ISO or reconvert its assets. Unchanged inputs reuse stat-bound SHA-256 receipts. The private index exposes a manifest and content-addressed blobs through the existing server's Host/Origin/join gates. Only missing, changed or damaged content is transferred by the app.

The Game Files screen supports caching from an authorized Mac origin, importing a prepared folder, verification, repair, cancellation and source selection. Prepared folders contain `zgta-resources.json` and `blobs/<sha256>`. Application Support storage survives normal app updates; deleting/resetting the app removes it. Verified blobs are shared across modes. Resources are excluded from backup and remain separate from multiplayer accounts and saves.

Installed mode resolves static assets locally and fails closed on missing, corrupt, invalid or unsupported resource requests. It does not fall back to a Mac asset server. Multiplayer still requires a reachable gameplay server. Development mode retains normal streaming when a matching verified cache is unavailable. Neither mode bypasses server authentication.

File hashes alone cannot activate an installation. The app also validates the declared world graph, native bootstrap geometry/atlas/collision, indexed model families, animation library, skin association and vehicle rig families using the actual native decoders. Every indexed family is checked sequentially. This does not decode every streamed world cell or prove original-game gameplay parity.

A stable format-validation identity is independent of the app build number. Restart/update reuse does not require importing the ISO again. Failed or cancelled preparation cannot replace the previously active catalogue. Operations retain Files-provider access until the worker completes and keep the screen awake only while foreground work owns a lease.

## Avoiding duplicate resources

The current owner-local prepared inventory contains 6,760 logical resources, about 2.46 GB. The older index additionally included 265 per-pedestrian baked animation files, about 5.49 GB. These are omitted only when bounded structural CLP1/SKN1 validation and the corresponding mesh count establish a usable modern replacement. Unknown, missing or malformed replacements retain the legacy file. Original archives are unchanged.

This is the existing prepared runtime's coverage. It is not proof that every file from the PC disc, every original audio bank or every radio track is consumed natively. Dynamic radio conversion and complete standalone resource conversion remain separate work.

## Source and tests

Public source contains the independently authored app, server, installer tool and tests. Original scripts, artwork, game data, generated manifests, path maps, game captures and private reference sources remain local.

Resource tests cover real HTTP gate behavior, source-root authorization, child-symlink escape rejection, atomic activation, cancellation, identity admission, zero-transfer reuse, changed/corrupt/missing blob repair, fail-closed reads and separate-process reopen. Small authored fixtures establish those contracts; actual game decoding and rendered device acceptance are recorded separately. The ISO bridge currently produces raw staged files; see `CORE_NATIVE_INSTALLER_107.md` for its remaining boundaries.
