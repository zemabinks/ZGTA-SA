#!/bin/zsh
set -euo pipefail
PHYSICS_ROOT="${0:A:h}"
PROJECT_ROOT="${PHYSICS_ROOT:h}"
source "$PHYSICS_ROOT/toolchain_env.sh"
export CARGO_TARGET_DIR="$PROJECT_ROOT/local-only/native-physics/target"
PHYSICS_OUTPUT="$PROJECT_ROOT/local-only/native-physics"
if [[ ! -x "$CARGO_HOME/bin/cargo" ]]; then
  print -u2 "The project-local Rust toolchain is missing at $CARGO_HOME/bin/cargo"
  exit 1
fi
build_target() {
  local physics_target="$1"
  local physics_directory="$2"
  local -a physics_flags=(--locked --release --jobs 2)
  [[ "${ZGTA_NATIVE_OFFLINE:-0}" != 1 ]] || physics_flags+=(--offline)
  cargo build "${physics_flags[@]}" --manifest-path "$PHYSICS_ROOT/Cargo.toml" --target "$physics_target"
  mkdir -p "$PHYSICS_OUTPUT/$physics_directory"
  cp "$CARGO_TARGET_DIR/$physics_target/release/libzgtasa_native_physics.a" "$PHYSICS_OUTPUT/$physics_directory/libzgtasa_native_physics.a.pending"
  mv "$PHYSICS_OUTPUT/$physics_directory/libzgtasa_native_physics.a.pending" "$PHYSICS_OUTPUT/$physics_directory/libzgtasa_native_physics.a"
  python3 "$PHYSICS_ROOT/source_stamp.py" write "$PHYSICS_OUTPUT/$physics_directory"
}
case "${1:-all}" in
  host)
    PHYSICS_HOST="$(rustc -vV | sed -n 's/^host: //p')"
    case "$PHYSICS_HOST" in
      aarch64-apple-darwin) build_target "$PHYSICS_HOST" macos-arm64 ;;
      x86_64-apple-darwin) build_target "$PHYSICS_HOST" macos-x86_64 ;;
      *) print -u2 "Unsupported native test host: $PHYSICS_HOST"; exit 2 ;;
    esac
    ;;
  ios)
    export IPHONEOS_DEPLOYMENT_TARGET=16.0
    build_target aarch64-apple-ios ios-device
    ;;
  sim)
    export IPHONEOS_DEPLOYMENT_TARGET=16.0
    build_target aarch64-apple-ios-sim ios-sim-arm64
    build_target x86_64-apple-ios ios-sim-x86_64
    mkdir -p "$PHYSICS_OUTPUT/ios-simulator"
    xcrun lipo -create "$PHYSICS_OUTPUT/ios-sim-arm64/libzgtasa_native_physics.a" "$PHYSICS_OUTPUT/ios-sim-x86_64/libzgtasa_native_physics.a" -output "$PHYSICS_OUTPUT/ios-simulator/libzgtasa_native_physics.a"
    python3 "$PHYSICS_ROOT/source_stamp.py" write "$PHYSICS_OUTPUT/ios-simulator"
    ;;
  mac)
    export MACOSX_DEPLOYMENT_TARGET=13.0
    build_target aarch64-apple-darwin macos-arm64
    build_target x86_64-apple-darwin macos-x86_64
    mkdir -p "$PHYSICS_OUTPUT/macos"
    xcrun lipo -create "$PHYSICS_OUTPUT/macos-arm64/libzgtasa_native_physics.a" "$PHYSICS_OUTPUT/macos-x86_64/libzgtasa_native_physics.a" -output "$PHYSICS_OUTPUT/macos/libzgtasa_native_physics.a"
    python3 "$PHYSICS_ROOT/source_stamp.py" write "$PHYSICS_OUTPUT/macos"
    ;;
  all)
    zsh "$PHYSICS_ROOT/build.sh" ios
    zsh "$PHYSICS_ROOT/build.sh" sim
    zsh "$PHYSICS_ROOT/build.sh" mac
    ;;
  *)
    print -u2 'Usage: native-physics/build.sh [all|host|ios|sim|mac]'
    exit 2
    ;;
esac
