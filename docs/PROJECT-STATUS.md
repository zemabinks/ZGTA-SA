# ZGTA:SA project status

**Snapshot date: 19 November 2026.** This page describes source and reported test evidence in the repository, **not** a guarantee of gameplay on every device. See the linked technical records for exact scope. New code may appear after this snapshot.

## At a glance

| Area | What the project has | What is not yet established |
| --- | --- | --- |
| **Native iOS client** | Swift/UIKit/Metal renderer, streaming, input, camera, physics, characters, vehicles, effects, audio and HUD; Xcode builds and selected rendered Simulator/device checks | Full GTA SA 1.0 US gameplay equivalence, all original content, stable performance on every iPhone |
| **Mac/browser development world** | Source-hosted local archive, independent Node server, guest accounts, shared lobby/gameplay systems | Complete feature equivalence with the original online service or a retail PC game |
| **iOS installed game resources** | Verified prepared resources can be imported or cached; installed mode reads static assets locally | Automatic full original-ISO-to-playable-native conversion and exhaustive resource coverage |
| **ISO** | Read-only ISO/InstallShield extraction of selected raw original resources, with retained checks | Native conversion of the extracted raw set and one-tap playable installation |
| **Browser ↔ native multiplayer** | Working connection and selected shared movement/vehicle/occupant tests; many incremental fixes | Full two-client vehicle/passenger/visual parity in all scenarios |
| **SA-MP/open.mp** | Separate experimental adapter with controlled legacy open.mp network/gameplay checks | Guaranteed compatibility with all SA-MP servers, extensions, modifications and content |
| **Original browser world's service** | Separate protocol/account integration; partial roster/scene verification | Full movement, combat, vehicles, missions and independent service interoperability |
| **Sandbox** | Many free-roam systems and simulation foundations | Complete original ambient traffic, pedestrians, police, world interactions and all behavior |
| **Public downloads** | Public source repository | No packaged public iPhone release in GitHub Releases |

## Latest verified implementation

Build 136 includes persisted resource-import corrections, owned/parked wheel-phase continuity, browser radio delivery and swimming-exit input/turn ownership fixes. Its source regressions, unsigned Simulator/device builds and selected normal Simulator import/join/walk/camera checks passed. Audio output, full hardware behavior and exhaustive original-retail parity remain unverified.

Repository cleanup is merged in [PR #3](https://github.com/zemabinks/ZGTA-SA/pull/3): 671 public files moved and the root reduced from 711 to 40 files. The full optional core chain, both SDK builds, source/history audit and corrected GitHub CI passed. Existing prepared resources were retained. The public launch commands remain available. See the [cleanup record](development/REPOSITORY-CLEANUP.md) for scope and validation.

Core 140 repairs independent-server breath lifetimes, stale HTTP breath-display writes and respawn oxygen clocks. Focused native-method and actual backend/Peer checks pass; full current regression and SDK validation are in progress. Rendered and hardware acceptance remain separate.

## Where we're going

The project's priorities are **stable shared world state**, **accurate player and vehicle appearances**, **correct passengers/vehicle authority**, **complete original resources**, **authentic NPCs and traffic**, and **original free-roam gameplay fidelity**. Original campaign missions are explicitly not the target.

An SA-MP player, a ZGTA:SA browser player and an iOS player do **not** automatically share a world unless they connect to the same compatible server/destination. “Perfect crossplay” across all servers or extensions has **not** been demonstrated.

## How status is verified

We distinguish **written source**, **unit/fixture tests**, **successful builds**, **Simulator gameplay**, **physical iPhone testing**, and **real multiplayer gameplay**. A passing synthetic test does not turn an experimental feature into a finished product.

For detailed evidence and gaps, see:

- [Feature matrix](development/FEATURE_MATRIX.md)
- [Core gameplay checklist](development/CORE_GAMEPLAY_PARITY.md)
- [Development journal](development/CORE_GAMEPLAY_JOURNAL.md)
- [Original-game reference](development/CORE_RETAIL_REFERENCE.md)
- [Server compatibility](development/SERVER_COMPATIBILITY.md)
- [Raw ISO extraction](research/resources/CORE_NATIVE_RAW_ISO_108.md)
- [Persistent resource storage](research/resources/CORE_NATIVE_RESOURCES_107.md)

**When updating this page:** reflect the latest tested revision, mention the exact scenario/platform, and leave untested items marked as unverified. Do not list unfinished source features as publicly downloadable.

[← All guides](README.md)
