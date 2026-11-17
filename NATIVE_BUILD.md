# Native gameplay builds

Gameplay uses optimized Swift Release by default. The Xcode scheme's Run and
Profile actions select Release; normal Debug remains available in Xcode and
through the build script:

For a fresh Mac, first install full [Xcode](https://developer.apple.com/xcode/)
and open it once to accept its license and install the iOS/Simulator platform.
Install [XcodeGen](https://github.com/yonaskolb/XcodeGen#installing) with
`brew install xcodegen` or its documented source/release installation. On Xcode26
the [Metal component](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)
is separate; install it with `xcodebuild -downloadComponent MetalToolchain` if
missing. Command Line Tools alone do not include the iPhone SDKs.

Install [Go](https://go.dev/dl/)1.26.4 or newer for the native SA-MP UDP
transport. Go1.27.2 is the tested version. Its standard library is sufficient;
this bridge does not fetch third-party Go modules. The pinned Apache2 transport
source, license and provenance are under `native-samp/`.

Then bootstrap this clone's own Rust and validate the native tools:

```sh
zsh native-physics/setup.sh
zsh native-physics/setup.sh --check
```

This installs/reuses official Rust1.100.0 under ignored `local-only/toolchains/`,
with targets `aarch64-apple-ios`, `aarch64-apple-ios-sim`, `x86_64-apple-ios`,
`aarch64-apple-darwin` and `x86_64-apple-darwin`. The installer uses rustup's
[`--no-modify-path` and custom homes](https://github.com/rust-lang/rustup/blob/main/doc/user-guide/src/installation/index.md);
it leaves global Rust and shell profiles alone. `--check` installs nothing,
checks the compiler/targets/SDKs/XcodeGen and compiles a tiny iPhone Metal kernel
in the clone's ignored cache. If Xcode is installed outside the selected
developer directory, run with its temporary `DEVELOPER_DIR` environment setting.

The tested tool versions are Xcode26.3(17C529), XcodeGen2.46.0 and Rust1.100.0
(0ef1bc386). The app targets iOS16; native Mac test libraries target macOS13.
These are the tested build tools, rather than an assertion that every earlier
Xcode version works. Browser hosting on macOS/Linux uses `host.py` and needs
none of these native build tools.

Build optimized gameplay:

```sh
zsh build_native.sh simulator
zsh build_native.sh device
zsh build_native.sh all
zsh build_native.sh simulator --debug
```

The script defaults to two build jobs and, for Release, two Swift compiler
threads. Set `ZGTA_BUILD_JOBS` or `ZGTA_SWIFT_THREADS` to an integer from 1 to 64
when a different concurrency budget is appropriate. Automatic parallel whole
module optimization is disabled explicitly: otherwise Xcode can append its
logical-CPU count after the requested thread flag and override that limit.

The complete frozen Core110 optimized Intel Simulator build passes in 1188.457s
with the emitted driver actually using two threads and all 202 inputs unchanged.
This establishes a complete optimized build, not iPhone FPS or a speed comparison
against builds run under different system load.

The [Definitive Edition menu](NATIVE_DE_MENU.md) optionally loads owner-provided
art/fonts/sounds from ignored `local-only/menu-bundle/OwnerMenu`. Without that
folder the source-only menu remains functional using text/color fallbacks.
Original resources must remain separate from public source and build uploads.

Use `build_native.sh` for either configuration. It selects `ios/project.yml`
when no owner manifest exists, so a clean checkout has no missing resource
reference. When `local-only/menu-bundle/OwnerMenu/manifest.json` exists, it selects
`ios/project-owner-menu.yml`, which includes the base spec and adds the required
local resource folder. An incomplete folder without a manifest uses the base
spec. XcodeGen's `optional` source setting only relaxes path validation; it does
not remove a resource reference from the generated project.

For manual project generation, run `cd ios && xcodegen generate --spec project.yml`
for the source-only configuration, or select `project-owner-menu.yml` after
importing the owner bundle. Regenerate when switching configurations. Verify
both isolated project-generation paths with `python3 smoke_native_project.py`;
this does not build the app or change the checkout's generated Xcode project.

The script regenerates XcodeGen, builds the required platform and prints the
bundle path under ignored `local-only/native-build/`. It does not boot Simulator,
install/launch an app or operate an attached device. `--derived-data PATH`
overrides the build output directory. Generic iPhone builds disable signing;
configure your development team in Xcode when installing on a physical phone.

The native physics static libraries must match the C/Swift bridge. If they are
absent, the script invokes `native-physics/build.sh all` using the project-local
Rust toolchain. Source stamps also detect bridge/header changes and rebuild
stale libraries after a source update. Missing Cargo packages are fetched
normally on a first build; `ZGTA_NATIVE_OFFLINE=1` is an optional cached-build
setting. All setup/build scripts work without relying on executable file modes.
The build also validates the Go transport's source/archive stamps and rebuilds
missing or stale iPhone and universal arm64/x86_64 Simulator libraries. To check
or rebuild the bridge separately:

```sh
python3 build_samp_transport.py --check --platform device --platform simulator
python3 build_samp_transport.py --test
```

The second command runs race-enabled host tests, builds both iOS platforms and
links the real C ABI against their SDKs. Cached libraries alone do not establish
server interoperability. See [server compatibility](SERVER_COMPATIBILITY.md)
for the separately verified join/gameplay boundaries.

Mac server launchers prepare runtime data separately with
`prepare_native_runtime.sh`; game assets remain under local-only.

An actual offline Intel Mac comparison of five panners and twenty vehicle voices
rendered 3.2 seconds of synthetic audio in 1.043 seconds with Swift `-O`, and
20.366 seconds with `-Onone`. That worst-case unoptimized path cannot render in
real time. These are desktop audio CPU-wall measurements while other builds
were running, not iPhone frame-rate results. Functional Debug builds remain
useful for diagnostics; evaluate gameplay/audio performance in Release and
profile the physical phone separately.


Core109's build also checks or builds the pinned native compressed-radio bridge:

```sh
python3 build_native_audio.py --check --platform device --platform simulator
```

Ordinary builds reuse matching source-stamped archives. The bridge includes
BSD-licensed Xiph source and one explicitly recorded upstream compatibility fix;
no game recordings or decoded audio belong in source. See
[native audio build provenance](native-audio/README.md). SDK links and CPU tests
do not establish audible device playback or frame-rate performance.


The complete Core109 Debug build passes for x86_64 Simulator and arm64 iPhone
with the same202 frozen build inputs. Only the dedicated Simulator is normally
updated; all four actual code/Metal payloads and preserved cache metadata are
verified. The device build remains unsigned/uninstalled. This is distinct from
the prior optimized Core108 timeouts and supplies no iPhone FPS measurement.
