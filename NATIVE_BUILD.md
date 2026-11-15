# Native gameplay builds

Gameplay uses optimized Swift Release by default. The Xcode scheme's Run and
Profile actions select Release; normal Debug remains available in Xcode and
through the build script:

```sh
zsh build_native.sh simulator
zsh build_native.sh device
zsh build_native.sh all
zsh build_native.sh simulator --debug
```

The script regenerates XcodeGen, builds the required platform and prints the
bundle path under ignored `local-only/native-build/`. It does not boot Simulator,
install/launch an app or operate an attached device. `--derived-data PATH`
overrides the build output directory. Generic iPhone builds disable signing;
configure your development team in Xcode when installing on a physical phone.

The native physics static libraries must match the C/Swift bridge. If they are
absent, the script invokes `native-physics/build.sh all` using the project-local
Rust toolchain. After changing the bridge, rebuild those libraries explicitly.
Mac server launchers prepare runtime data separately with
`prepare_native_runtime.sh`; game assets remain under local-only.

An actual offline Intel Mac comparison of five panners and twenty vehicle voices
rendered 3.2 seconds of synthetic audio in 1.043 seconds with Swift `-O`, and
20.366 seconds with `-Onone`. That worst-case unoptimized path cannot render in
real time. These are desktop audio CPU-wall measurements while other builds
were running, not iPhone frame-rate results. Functional Debug builds remain
useful for diagnostics; evaluate gameplay/audio performance in Release and
profile the physical phone separately.
