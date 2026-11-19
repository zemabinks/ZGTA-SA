# Vehicle phase continuity and local radio intake

Owned vehicles now hand their front and rear visual wheel counters to the
unattended vehicle before releasing the owned solver. Taking a parked vehicle
retains its complete snapshot until the new solver accepts it, then restores
those counters once. Deferred model admission keeps that snapshot. Session,
passenger, teleport and terminal transitions retire the pending owner. The raw
renderer uses these counters only when a physical or pending owner supplies
them; its fallback vehicle animation remains available.

This is a visual continuity correction. It does not change velocity, handling,
collision response or network packets. Browser entity and singleton ownership
differ, and this policy has not been verified against retail wheel animation.

The normal iOS ISO picker now supports Files/Finder document sharing. Raw audio
can accompany an existing prepared native installation; extracting raw files
alone does not convert or activate the native world. See
[the local radio instructions](RADIO_OWNER_IMPORT.md).

The importer handles a mixed-case directory only after an exact descriptor
lookup reports absence and directory creation reports an existing entry. It
requires a unique bounded case alias, opens it without following links and
keeps the original directory/type checks. While checking the new extraction
stage, the Swift store records each file's actual resolved spelling. Saved
receipts and later decoder leases retain strict path traversal. Failed imports
leave the previous catalogue and prepared installation intact.

Focused authored tests cover actual solver/owner transitions at multiple frame
cadences, deferred entry, parked counter retention, raw-renderer fallback,
descriptor aliases, ambiguity, symlinks, bounds, cancellation, receipt reuse
and strict lease reads. The C traversal test uses address and undefined-behavior
sanitizers. Historical implementations fail the respective wheel-transfer and
directory-alias assertions. Host radio tests use authored compressed recordings
without starting audio output.

Run `python3 smoke_core_130.py` for the selected source suite. With separately
built source-stamped host libraries, add `--with-physics` and `--with-audio`.
Normal-menu original-file intake, rendered motion, audible playback, physical
controls and retail timings require separate acceptance. Passing these tests
does not establish complete San Andreas parity.
