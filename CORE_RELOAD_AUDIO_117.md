# Core117 reload audio ownership

An old reload could request its second sound after the player changed weapons,
died, teleported, entered a vehicle or changed multiplayer sessions. Its queued
callback did not belong to a particular reload. A sample that was still loading
could also play after that task ended.

`NativeGameAudio` now assigns each reload a generation. Cancellation invalidates
both its delayed phase and pending sample completions. Accepted weapon changes,
explicit reload rejection, death, accepted vehicle entry, authoritative
placement, respawn and connection replacement cancel that owner. Audio
suspension and shutdown also invalidate it, preventing resume from reviving an
old phase. A fresh reload after resuming works normally.

Input-only `resetControls()` does not cancel a continuing reload. Same-weapon
inventory updates and successful reload replies preserve its audio. Already
playing one-shots remain committed, and shot/blast sounds use their existing
independent admission. The existing normal420ms second-phase delay is retained;
this change does not establish original clip-aligned reload timing.

The owner-local archived browser's normal reload uses a phase timer that is
cleared by selected-weapon changes. That supports the cancellation discrepancy.
Its separate420ms shot-after-sound path is distinct and was not used as the
reference for normal reload cancellation. Original scripts, samples and static
game data remain local.

The focused asset-free gate compiles actual audio methods, actual controller
callbacks and the connection ready/nonready prefix with inert audio, schedule,
sample-delivery and UI adapters:

```sh
python3 -B smoke_native_reload_audio.py
```

The optional `--historical-root PATH` runs literal prior audio methods as
negative controls. The default needs no previous checkout or game assets.
Neither mode opens an audio device, network connection, browser or Simulator.

A successful climb also notifies the audio owner after it replaces an active
reload animation. Rejected ledges, unavailable resources and input-only resets
do not send that notification. The existing owner-local climb runtime gate
checks this with actual animation clips, collision queries and audio methods.
Other internal task resets still need individual ownership review. Retail
timing, audible device playback and complete combat parity remain unverified.
