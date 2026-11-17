The independent bridge, wrappers, build tooling and tests use AGPL-3.0-only.

The unmodified library subset in vendor/unshield uses the MIT license retained
in vendor/unshield/LICENSE. Its source repository and pinned revision are listed
in vendor/unshield/PROVENANCE.json. The small staged unsigned-read correction is
recorded separately under patches/ and retains the upstream notice.

Apple CommonCrypto and system zlib are linked from the platform SDK/system;
their implementation bytes are not redistributed in this source tree. The
upstream RSA MD5 implementation is not vendored.

No Rockstar game resources, ISO/CAB contents, saves, credentials or compiled
library/application payloads are included in this public source directory.
