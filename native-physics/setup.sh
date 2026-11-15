#!/bin/zsh
# Installs only the project-local official Rust toolchain. Apple/XcodeGen
# prerequisites are checked, with explicit instructions for missing components.
set -euo pipefail
PHYSICS_ROOT="${0:A:h}"
PROJECT_ROOT="${PHYSICS_ROOT:h}"
PHYSICS_CHECK=0
case "${1:-}" in
  '') ;;
  --check) PHYSICS_CHECK=1 ;;
  *) print -u2 'Usage: zsh native-physics/setup.sh [--check]'; exit 2 ;;
esac
[[ "$(uname -s)" == Darwin ]] || { print -u2 'Native iOS builds require macOS. Browser hosting uses host.py on macOS/Linux.'; exit 1; }
export RUSTUP_HOME="$PROJECT_ROOT/local-only/toolchains/rustup"
export CARGO_HOME="$PROJECT_ROOT/local-only/toolchains/cargo"
export PATH="$CARGO_HOME/bin:$PATH"
export RUSTUP_AUTO_INSTALL=0
# A parent shell's Mac SDK must not override an explicit iPhone compilation.
unset SDKROOT
PHYSICS_MISSING=0
if ! source "$PHYSICS_ROOT/toolchain_env.sh" 2>/dev/null; then
  if (( PHYSICS_CHECK )); then
    print -u2 'Missing project-local Rust1.100.0; run this script without --check.'
    PHYSICS_MISSING=1
  else
    mkdir -p "$PROJECT_ROOT/local-only/toolchains"
    if [[ ! -x "$CARGO_HOME/bin/rustup" ]]; then
      PHYSICS_INSTALLER="$PROJECT_ROOT/local-only/toolchains/rustup-init.sh"
      curl --proto '=https' --tlsv1.2 --fail --show-error --location https://sh.rustup.rs -o "$PHYSICS_INSTALLER"
      bash "$PHYSICS_INSTALLER" -y --no-modify-path --profile minimal --default-toolchain none
    fi
    "$CARGO_HOME/bin/rustup" toolchain install 1.100.0 --profile minimal
    export RUSTUP_TOOLCHAIN=1.100.0
    source "$PHYSICS_ROOT/toolchain_env.sh"
  fi
fi
PHYSICS_TARGETS=(aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios aarch64-apple-darwin x86_64-apple-darwin)
if [[ -x "$CARGO_HOME/bin/rustc" ]] && "$CARGO_HOME/bin/rustc" --version 2>/dev/null | /usr/bin/grep -q '^rustc 1\.100\.0 '; then
  print "$PHYSICS_RUST_VERSION"
  if (( PHYSICS_CHECK )); then
    PHYSICS_INSTALLED="$("$CARGO_HOME/bin/rustup" target list --installed)"
    for PHYSICS_TARGET in "${PHYSICS_TARGETS[@]}"; do
      if [[ $'\n'"$PHYSICS_INSTALLED"$'\n' != *$'\n'"$PHYSICS_TARGET"$'\n'* ]]; then
        print -u2 "Missing Rust target: $PHYSICS_TARGET"; PHYSICS_MISSING=1
      fi
    done
  else
    "$CARGO_HOME/bin/rustup" target add "${PHYSICS_TARGETS[@]}"
  fi
fi
if ! command -v xcodebuild >/dev/null || ! xcodebuild -version; then
  print -u2 'Install/open full Xcode and accept its license; Command Line Tools alone do not include the iPhone SDKs.'
  PHYSICS_MISSING=1
fi
PHYSICS_SDK="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)"
if [[ ! -d "$PHYSICS_SDK" ]] || ! xcrun --sdk iphonesimulator --show-sdk-path >/dev/null 2>&1; then
  print -u2 'Install the iOS platform/Simulator SDKs in Xcode Settings > Components.'
  PHYSICS_MISSING=1
fi
if command -v xcodegen >/dev/null; then xcodegen --version
else print -u2 'Install XcodeGen: brew install xcodegen'; PHYSICS_MISSING=1; fi
metal_check() {
  [[ -d "$PHYSICS_SDK" ]] || return 1
  local physics_check_dir="$PROJECT_ROOT/local-only/toolchains/metal-check"
  local physics_developer="$(xcode-select -p 2>/dev/null || true)"
  local physics_default="$(xcrun --sdk iphoneos --find metal 2>/dev/null || true)"
  local physics_compiler
  local -a physics_compilers
  physics_compilers=("$physics_default" "$HOME"/Library/Developer/DVTDownloads/MetalToolchain/mounts/*/Metal.xctoolchain/usr/bin/metal(N) "$physics_developer"/Toolchains/*/usr/bin/metal(N))
  mkdir -p "$physics_check_dir"
  cat > "$physics_check_dir/check.metal" <<'SHADER'
#include <metal_stdlib>
using namespace metal;
kernel void native_toolchain_check(device uint *v [[buffer(0)]], uint id [[thread_position_in_grid]]) { v[id] = id; }
SHADER
  for physics_compiler in "${physics_compilers[@]}"; do
    [[ -x "$physics_compiler" ]] || continue
    if "$physics_compiler" -c "$physics_check_dir/check.metal" -target air64-apple-ios16.0 -isysroot "$PHYSICS_SDK" \
        -fmodules-cache-path="$physics_check_dir/modules" -o "$physics_check_dir/check.air" > "$physics_check_dir/compile.log" 2>&1; then
      print 'PASS: iPhone Metal compiler'; return 0
    fi
  done
  return 1
}
if ! metal_check; then
  print -u2 'Install the Xcode Metal Toolchain component: xcodebuild -downloadComponent MetalToolchain'
  PHYSICS_MISSING=1
fi
(( PHYSICS_MISSING == 0 )) || exit 1
print 'Native toolchain ready. Rust/cargo/cache stay in local-only; shell profiles and global Rust were not changed.'
