#!/bin/zsh
# Sourced by native build scripts; never changes a global Rust installation.
: "${PROJECT_ROOT:?Set PROJECT_ROOT before loading the native toolchain}"
export RUSTUP_HOME="$PROJECT_ROOT/local-only/toolchains/rustup"
export CARGO_HOME="$PROJECT_ROOT/local-only/toolchains/cargo"
export PATH="$CARGO_HOME/bin:$PATH"
export RUSTUP_AUTO_INSTALL=0
PHYSICS_REQUIRED_RUST=1.100.0
if [[ ! -x "$CARGO_HOME/bin/rustc" ]]; then
  print -u2 'Project-local Rust is missing. Run: zsh native-physics/setup.sh'
  return 1
fi
PHYSICS_RUST_VERSION="$("$CARGO_HOME/bin/rustc" --version 2>/dev/null || true)"
if [[ "$PHYSICS_RUST_VERSION" != "rustc $PHYSICS_REQUIRED_RUST "* ]]; then
  export RUSTUP_TOOLCHAIN="$PHYSICS_REQUIRED_RUST"
  PHYSICS_RUST_VERSION="$("$CARGO_HOME/bin/rustc" --version 2>/dev/null || true)"
fi
if [[ "$PHYSICS_RUST_VERSION" != "rustc $PHYSICS_REQUIRED_RUST "* ]]; then
  print -u2 "Native physics requires Rust $PHYSICS_REQUIRED_RUST. Run: zsh native-physics/setup.sh"
  return 1
fi
