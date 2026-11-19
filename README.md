# ZGTA:SA

**An experimental GTA: San Andreas free-roam and multiplayer project for iPhone and iPad, built with Swift and Apple's Metal graphics API.**

ZGTA:SA is a work-in-progress, independently developed native iOS client, with an optional self-hosted browser world and experimental connections to other multiplayer services. The goal is a faithful San Andreas sandbox where players can see the same characters, vehicles, customizations and interactions, whichever supported client they use.

> **Development project — not a finished game download.** There is currently **no packaged public iOS release** in this repository. The original GTA: San Andreas game files are **not included**. An ISO can be inspected and its raw resources extracted, but selecting the ISO does **not yet** create a fully playable native installation.

**[Start here](docs/START-HERE.md)** · **[Game files & ISO](docs/GAME-FILES.md)** · **[Play with friends](docs/MULTIPLAYER.md)** · **[Build for iPhone](docs/development/BUILD-IOS.md)** · **[Get help](docs/TROUBLESHOOTING.md)**

## What is ZGTA:SA?

- **Native iOS game client:** Swift, UIKit, Metal, and native physics, animation, vehicle, combat and world systems. This is a reconstruction, not the original Windows executable running on iPhone.
- **Your own multiplayer world:** a local server and browser client that can share a session with the native iOS client. Gameplay synchronization is still being improved.
- **Other server options:** development-stage SA-MP/open.mp and original-browser-world adapters, each with different limitations.
- **Original game resources:** tools for preparing owned San Andreas assets, verified local iOS resources and Mac-assisted development.

**Focus:** free-roam gameplay, pedestrians, traffic, vehicles, interactions and faithful shared multiplayer. **Recreating the original story campaign is not the goal.**

## What can I use today?

| Option | Current availability |
| --- | --- |
| **Mac/browser: self-hosted development world** | Source setup is available. Requires Python, Node.js, a compatible browser and the prepared game archive. |
| **iPhone/iPad: native Metal client** | Build from source with Xcode. Target is **iOS/iPadOS 16+**; functionality varies by device and build. |
| **Original GTA SA 1.0 US ISO import** | Raw-file extraction and verification exist. **Automatic ISO → playable native game conversion is unfinished.** |
| **Verified prepared game files on iOS** | Development caching and an installed-resource mode exist; see the actual requirements and restrictions in the [game files guide](docs/GAME-FILES.md). |
| **SA-MP/open.mp and original browser service** | Partial, experimental compatibility. **Not guaranteed on arbitrary servers.** |

See the [dated project status](docs/PROJECT-STATUS.md) for what has actually been tested and what is still missing.

## Quick start: try the Mac/browser development world

First install **Python 3.9+** and **Node.js 22+**. On your Mac, open Terminal and enter:

```sh
git clone https://github.com/zemabinks/ZGTA-SA.git
cd ZGTA-SA
python3 host.py setup --download
python3 host.py doctor
python3 host.py serve
```

Keep Terminal open and open **http://127.0.0.1:8766/** in a compatible browser. The initial archive/setup needs the relevant source files to be accessible; this is not a substitute for owning the original PC game. For first-time users, the [step-by-step guide](docs/START-HERE.md) explains what each command does.

**Want the iPhone app instead?** There is no public IPA to download yet. Follow the [native build guide](docs/development/BUILD-IOS.md) and [game-file instructions](docs/GAME-FILES.md). Downloading this repository as a ZIP does **not** install an iPhone app.

## Playing together

ZGTA:SA's own server, external SA-MP/open.mp servers, and the original **play.samp.directory** service are **different multiplayer worlds**. They do not automatically share players. The aim is accurate cross-platform representation **when players are actually connected to the same supported server**.

Read [Host or join multiplayer](docs/MULTIPLAYER.md) before trying mixed browser/iOS or external-server sessions. Vehicle seats, custom content and complete visual parity are still active development targets.

## Source, safety and credits

This repository contains **project source code and tools**, not Rockstar's game files, copyrighted archives, private website bundles, account data or compiled releases. Users must supply game content they are entitled to use. Do not upload original game files or credentials in issues.

Source is **AGPL-3.0-only**; third-party components have their own notices. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md). This is an independent fan development effort, **not affiliated with or endorsed by Rockstar Games**.

**For developers:** [Project map](docs/development/PROJECT-MAP.md) · [Technical documentation](docs/DEVELOPMENT.md) · [Detailed feature matrix](docs/development/FEATURE_MATRIX.md) · [Proposed safe repository cleanup](docs/development/REPOSITORY-CLEANUP.md).
