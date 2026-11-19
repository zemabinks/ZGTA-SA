# Native menu regressions

Run on a Mac with Xcode's Swift tools and Node:

```sh
python3 tests/ui/smoke_native_menu_profile.py
python3 tests/ui/smoke_native_menu_keys.py
python3 tests/ui/smoke_native_bindings.py
```

The profile suite preserves the original25 management checks and adds45 connection checks. It compiles the actual `NativeMenuProfileClient`, `ServerAddress` and extracted `LocalGuestSession`, then connects over real HTTP to temporary backend copies with synthetic accounts on random loopback ports. It tests fresh and restored guests, per-server identity, missing/rejected/accepted join codes, real access-cookie authorization, malformed status/authentication, redirects at status/join/auth, cancellation during delayed status/auth and replacement by a newer connection. The fixture's forwarded address exercises the backend's remote-visitor authorization path rather than its trusted-localhost bypass. Temporary saved guest entries are removed afterward; the fixture does not use player saves from the host project.

The key suite runs the real `NativeMenuKeyLatch`, actual extracted menu wrapper and actual extracted menu/game press handlers. It verifies shared parent/child repeat suppression, release delivered to either responder, Options Escape closing into the game, no intermediate Escape/Space/Return/arrow repeat entering gameplay, the next fresh press, normal gameplay Escape behavior, cancellation, backgrounding and keyboard disconnect. UIKit event types and lifecycle notification names are small test carriers; this is a source-dispatch regression, not a physical-keyboard or Simulator acceptance claim.

The raw latch belongs to the menu until release. The game checks ownership before adding a held key, forwards key-up into the latch and clears it on cancellation. The menu wrapper clears ownership on resign-active/keyboard-disconnect, and the connection screen clears it before transferring to a newly created game. Releases are shared; submenu appearance must not reset the latch, or the opening key's repeat could activate the destination too.

Core85 preserves those27 checks and adds34 responder-chain checks, for61 total. Unlike the earlier leaf-only responder stub, the test now propagates `super.pressesBegan` into the presenting Home, then the title menu and a terminal responder. Exact prior Core84 handler specimens in `test-fixtures/native-menu/core84-responder-handlers.json` reproduce Escape opening Pause and also calling the presenting menu's close handler, plus Space reaching its activation handler. The fixture records hashes of the original project source and the extracted methods; it contains only this project's AGPL source, with no game assets.

Current Core85 handlers consume game-owned keyboard events and ignore menu actions behind a presented child. Only non-keyboard presses propagate to `super`, including mixed Escape/Space batches and offline/inactive/modal early returns. Unknown keys retain ordinary default forwarding in menu screens without triggering a menu action. These checks execute actual extracted handlers against minimal UIKit type carriers; they do not claim that a presenting menu's activation dispatch necessarily completed a network connection or that physical keyboard behavior was measured. Installed App acceptance is separate.

Reports and source hashes remain in ignored `local-only/native-physics/tests/menu-profile` and `menu-keys`. Full App builds and actual device/UI acceptance are separate. Network cancellation suppresses client callbacks/follow-up requests; it cannot undo a server action that was already accepted.
