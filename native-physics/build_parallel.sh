#!/bin/zsh
# Isolated Cargo output directories allow independent Apple targets to compile
# concurrently without Cargo's shared build-directory lock.
set -euo pipefail
PHYSICS_ROOT="${0:A:h}"
PROJECT_ROOT="${PHYSICS_ROOT:h}"
export RUSTUP_HOME="$PROJECT_ROOT/local-only/toolchains/rustup"
export CARGO_HOME="$PROJECT_ROOT/local-only/toolchains/cargo"
export IPHONEOS_DEPLOYMENT_TARGET=16.0
export MACOSX_DEPLOYMENT_TARGET=13.0
PHYSICS_OUTPUT="$PROJECT_ROOT/local-only/native-physics"
PHYSICS_WORKERS="${1:-3}"
[[ "$PHYSICS_WORKERS" == [1-4] ]] || { print -u2 'Usage: build_parallel.sh [workers1..4]'; exit 2; }
mkdir -p "$PHYSICS_OUTPUT/parallel-targets" "$PHYSICS_OUTPUT/build-logs"
build_one() {
  local physics_target="$1" physics_directory="$2"
  local physics_cache="$PHYSICS_OUTPUT/parallel-targets/$physics_target"
  mkdir -p "$physics_cache"
  if [[ ! -d "$physics_cache/$physics_target" && -d "$PHYSICS_OUTPUT/target/$physics_target" ]]; then
    cp -cR "$PHYSICS_OUTPUT/target/$physics_target" "$physics_cache/"
  fi
  if [[ ! -d "$physics_cache/release" && -d "$PHYSICS_OUTPUT/target/release" ]]; then
    cp -cR "$PHYSICS_OUTPUT/target/release" "$physics_cache/"
  fi
  print "Building native physics: $physics_target"
  if ! CARGO_TARGET_DIR="$physics_cache" "$CARGO_HOME/bin/cargo" build --locked --offline --release --jobs 2 --manifest-path "$PHYSICS_ROOT/Cargo.toml" --target "$physics_target" > "$PHYSICS_OUTPUT/build-logs/$physics_target.log" 2>&1; then
    tail -45 "$PHYSICS_OUTPUT/build-logs/$physics_target.log"
    return 1
  fi
  mkdir -p "$PHYSICS_OUTPUT/$physics_directory"
  cp "$physics_cache/$physics_target/release/libzgtasa_native_physics.a" "$PHYSICS_OUTPUT/$physics_directory/libzgtasa_native_physics.a.pending"
  mv "$PHYSICS_OUTPUT/$physics_directory/libzgtasa_native_physics.a.pending" "$PHYSICS_OUTPUT/$physics_directory/libzgtasa_native_physics.a"
  print "Built native physics: $physics_target"
}
PHYSICS_PIDS=()
PHYSICS_FAILURE=0
wait_batch() {
  local physics_pid
  for physics_pid in "${PHYSICS_PIDS[@]}"; do
    if ! wait "$physics_pid"; then PHYSICS_FAILURE=1; fi
  done
  PHYSICS_PIDS=()
}
for PHYSICS_ITEM in 'aarch64-apple-ios:ios-device' 'aarch64-apple-ios-sim:ios-sim-arm64' 'x86_64-apple-ios:ios-sim-x86_64' 'aarch64-apple-darwin:macos-arm64' 'x86_64-apple-darwin:macos-x86_64'; do
  build_one "${PHYSICS_ITEM%%:*}" "${PHYSICS_ITEM#*:}" &
  PHYSICS_PIDS+=("$!")
  if (( ${#PHYSICS_PIDS} >= PHYSICS_WORKERS )); then wait_batch; fi
done
wait_batch
(( PHYSICS_FAILURE == 0 )) || exit 1
mkdir -p "$PHYSICS_OUTPUT/ios-simulator" "$PHYSICS_OUTPUT/macos"
xcrun lipo -create "$PHYSICS_OUTPUT/ios-sim-arm64/libzgtasa_native_physics.a" "$PHYSICS_OUTPUT/ios-sim-x86_64/libzgtasa_native_physics.a" -output "$PHYSICS_OUTPUT/ios-simulator/libzgtasa_native_physics.a.pending"
mv "$PHYSICS_OUTPUT/ios-simulator/libzgtasa_native_physics.a.pending" "$PHYSICS_OUTPUT/ios-simulator/libzgtasa_native_physics.a"
xcrun lipo -create "$PHYSICS_OUTPUT/macos-arm64/libzgtasa_native_physics.a" "$PHYSICS_OUTPUT/macos-x86_64/libzgtasa_native_physics.a" -output "$PHYSICS_OUTPUT/macos/libzgtasa_native_physics.a.pending"
mv "$PHYSICS_OUTPUT/macos/libzgtasa_native_physics.a.pending" "$PHYSICS_OUTPUT/macos/libzgtasa_native_physics.a"
print 'Built native physics for all Apple targets'
