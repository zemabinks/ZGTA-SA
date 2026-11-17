# Native original-resource extraction bridge

Core107 includes a bounded Apple C/Swift utility for reading an owner-supplied
ISO and extracting selected original resources into a new staging folder. It
does not run Windows executables or installers. **Raw extraction is not native
conversion, a playable installation or completed App integration.**

## Implemented boundary

The bridge indexes primary ISO9660 metadata, validates the InstallShield header
and reads cabinet ranges directly from the same read-only ISO descriptor. It
does not copy whole cabinets or load the whole ISO into memory. File-group,
directory and filename relationships are retained, including extensionless
radio streams. The full catalogue remains available for inspection.

The default raw selection retains the anim, data, models, text, audio and movies
roots. It excludes Windows executable/library components, installer containers
and support/HOODLUM extras. Retaining a raw resource does not assert that its
native converter exists. Unsafe or duplicate destination identities, malformed
metadata, byte/count limits and unsupported layouts fail rather than creating a
successful installation result.

Extraction requires a new stage beneath an existing canonical app-owned parent.
Archive-controlled descendants use directory-relative no-follow traversal and
exclusive temporary files. Cancellation or failure removes that new stage;
active installed resources are never its destination. The original ISO is not
modified. Persistent raw-extraction job resumption is not implemented.

`NativeISOExtraction` is a synchronous worker interface. Its caller must retain
Files security-scoped access for the operation, keep work off the UI thread and
serialize use of an instance. Progress callbacks run on that worker. The API
offers catalogue inspection, `gameResources()`, `extractGameResources(to:)`, an
explicit index selection for controlled investigation, cancellation and read/
write statistics. See [the bridge documentation](native-installer/README.md)
and [the C boundary](native-installer/include/zgtasa_installer.h).

## Source and licensing

The bridge, Swift wrappers, tooling and tests are independently authored
AGPL-3.0-only source. The unchanged unshield library subset is pinned to
`3914dffb32ad05ebcb3e7f64a033e69b59127f47`, with its MIT license and per-file
provenance retained under `native-installer/vendor/unshield/`. The upstream RSA
MD5 implementation is omitted; the compatibility adapter calls Apple
CommonCrypto for the cabinet format's consistency check.

One explicit build-stage patch changes the pinned little-endian reader's byte
shifts to unsigned arithmetic. UBSan reproduced signed-shift overflow in the
original reader on owner metadata. The patch preserves the intended values and
accepted extraction hashes; pristine vendored files remain unchanged. Build
receipts record pristine and staged hashes.

The public source guard admits the exact authored files and pinned vendor
subset. Its only JSON exceptions in this directory are
`vendor/unshield/PROVENANCE.json` and `patches/unsigned-le32.json`. No original
resource, ISO, cabinet, owner inventory, save, credential, compiled library or
captured test fixture is included in this source directory.

## Verification

On a Mac with the existing Xcode SDKs:

```sh
python3 build_installer_bridge.py --link-probes
python3 smoke_native_installer_bridge.py
python3 check_public_source.py --directory
```

Without owner arguments the extraction test checks synthetic selection and
invalid-source boundaries. Actual owner-media checks are a separate invocation:

```sh
python3 smoke_native_installer_bridge.py --iso /absolute/path/original.iso --accepted-root /absolute/path/accepted/resources
```

The recorded owner run passed 189 checks: 499 catalogue entries, 409 default raw
resources, six exact relative cabinet paths matching independently accepted
SHA-256s, and a loose extensionless radio stream matching an independently
indexed ISO range. Cancellation, existing-stage protection, output limits,
duplicate destinations and malformed metadata/cabinet rollback were exercised.
The current C source also passed ASan/UBSan with actual extraction, eight
malformed metadata cases and 20 malformed-cabinet retries.

A separate bounded split-volume check extracted the original 1.1GB `SPC_GA`
member directly across cabinets, verified its original header checksum and a
streamed SHA-256, and removed the temporary stage. That one check preceded only
the subsequent parent-directory opening refinement; the final host suite and
sanitizer run tested that refinement. The full 409-resource selection has not
been extracted and accepted as a complete native installation by these tests.

Static archives and actual Swift/C linking passed for the host, arm64 iOS
device, arm64 Simulator and x86_64 Simulator; a universal Simulator archive and
all ten C API exports were verified. Outputs and source receipts remain under
ignored `local-only/native-installer/` and `local-only/research/native-installer-107/`.
Compilation/linking does not establish Files-provider behavior, iOS sandbox
runtime, phone throughput, thermal performance or rendered gameplay acceptance.

## Remaining integration

The App build must explicitly compile the Swift boundary, include the
`CZGTAInstaller` module, link the matching platform archive and system zlib, and
retain the caller's security scope through cancellation completion. This utility
is not yet the GAME screen's extraction action. The existing inspection and
prepared-folder workflows must not describe raw extraction as playable success.

Original path spelling is retained, including case differences between cabinet
and loose ISO roots. A downstream converter needs a case-insensitive complete
resource identity index with ambiguous duplicates rejected. It must then
perform the actual format conversions, produce and verify the prepared-resource
schema, and activate it through the resource store. Converter coverage, supported
edition identification, repair/resume policy and standalone/offline runtime
acceptance remain separate requirements. No second game engine is introduced.
