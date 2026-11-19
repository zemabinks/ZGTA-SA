# Build ZGTA:SA for iPhone or Simulator

This is for **developers/testers with a Mac**. There is currently **no packaged public IPA**. Building the code does **not** provide Rockstar's game files.

**Target platform:** iOS/iPadOS **16.0+** in the project settings. This is a compilation target, **not** a guarantee of good performance or compatibility with every device.

## What you need

- A Mac with **full Xcode** installed, opened once so the license and iOS/Simulator components are available.
- **XcodeGen** to generate the Xcode project.
- The project's Rust toolchain for native physics and the Go toolchain for the SA-MP transport.
- Python 3.9+ and Node.js 22+ for resource preparation and the independent host.
- The appropriate **owned or otherwise authorized game resources**, already prepared into the native data format (or access to an existing development Mac asset server).

Read [NATIVE_BUILD.md](../../NATIVE_BUILD.md) for exact tested compiler versions, instructions and build switches. Do not assume only installing Xcode is sufficient.

## Step 1: Get the source

In Terminal:

```sh
git clone https://github.com/zemabinks/ZGTA-SA.git
cd ZGTA-SA
```

If you're working on an existing checkout, **do not clone over it or replace its local-only data**.

## Step 2: Prepare the build tools

Install XcodeGen using its documented method; on a Mac with Homebrew:

```sh
brew install xcodegen
```

Follow the [native build guide](../../NATIVE_BUILD.md) to install Go and to obtain the Xcode Metal toolchain component if your Xcode build requires it. Then run the project's isolated Rust setup:

```sh
zsh native-physics/setup.sh
zsh native-physics/setup.sh --check
```

This uses project-local toolchain paths where supported; you don't need to change your global Rust environment just for this repository.

## Step 3: Prepare data for the native renderer

Follow the [hosting/native asset preparation instructions](../../HOSTING.md#native-ios-clients). The documented source-preparation path is:

```sh
python3 -m venv local-only/venv
local-only/venv/bin/python -m pip install -r requirements-native.txt
local-only/venv/bin/python host.py setup --native
```

If you have no usable local browser archive yet, the hosting guide describes `--download`. **It depends on source availability.** Raw original ISO extraction is **not yet** a replacement for this prepared-resource pipeline.

When developing against an existing Mac resource server, the app can reuse its verified cache. You should not have to reimport gigabytes after every normal Xcode rebuild. See [Game files](../GAME-FILES.md).

## Step 4: Build

From the repository root, choose one:

```sh
zsh build_native.sh simulator
```

```sh
zsh build_native.sh device
```

Or use `zsh build_native.sh all` for both. The command builds and reports the output under ignored `local-only/native-build/`. **It does not automatically boot Simulator, install the app, sign it for your phone or start multiplayer.**

To create/open the source project manually, follow [NATIVE_BUILD.md](../../NATIVE_BUILD.md) for the exact XcodeGen configuration. A real iPhone install needs your own Xcode code-signing team.

## Step 5: Run the game

1. Launch the generated Xcode project in Xcode.
2. Select a compatible iPhone or Simulator target.
3. For a physical iPhone, set valid signing under the app target.
4. Build and run the application.
5. Open **GAME → GAME FILES** and choose your verified local resources or **USE DEVELOPMENT RESOURCES** with your Mac's server.
6. Open **MULTIPLAYER** and connect to a compatible independent or experimental supported server.

**Important:** the Mac address in an iPhone screen must be its **LAN IP**; `127.0.0.1` on the iPhone is not your Mac.

## Testing and preserving work

Run the relevant existing smoke tests before marking a change verified. The repository includes extensive `smoke_*.py`, `smoke_*.js`, `smoke_*.swift` and other test scripts. For a baseline overview, see [FEATURE_MATRIX.md](FEATURE_MATRIX.md) and [CORE_GAMEPLAY_JOURNAL.md](CORE_GAMEPLAY_JOURNAL.md).

Keep `local-only/`, player accounts, saves, original disc images and downloaded game content **outside public Git commits**. Keep useful local Git checkpoints. Fewer GitHub pushes are fine; do not risk losing work by leaving the only copy on an unreliable drive.

[← Developer docs](../DEVELOPMENT.md)
