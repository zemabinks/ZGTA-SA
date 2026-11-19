#!/bin/zsh
# Independent literal-Ball ABI/filter tests. Build matching libraries first;
# this gate never installs tools or changes a running app/server.
set -euo pipefail
PHYSICS_ROOT="${0:A:h}"
PROJECT_ROOT="${PHYSICS_ROOT:h}"
PHYSICS_OUTPUT="$PROJECT_ROOT/local-only/native-physics/tests/sphere"
case "$(uname -m)" in
  arm64) PHYSICS_HOST_DIR=macos-arm64; PHYSICS_HOST_TRIPLE=arm64-apple-macosx13.0 ;;
  x86_64) PHYSICS_HOST_DIR=macos-x86_64; PHYSICS_HOST_TRIPLE=x86_64-apple-macosx13.0 ;;
  *) print -u2 'This gate requires a supported macOS native host.'; exit 2 ;;
esac
PHYSICS_LIBRARY="$PROJECT_ROOT/local-only/native-physics/$PHYSICS_HOST_DIR"
if ! python3 "$PHYSICS_ROOT/source_stamp.py" check "$PHYSICS_LIBRARY"; then
  print -u2 'Build the matching native host library before this gate: zsh native-physics/build.sh host';exit 2
fi
mkdir -p "$PHYSICS_OUTPUT"
PHYSICS_SNAPSHOT="$(mktemp -d "$PHYSICS_OUTPUT/run-XXXXXXXX")"
trap 'rm -rf "$PHYSICS_SNAPSHOT"' EXIT
cp "$PHYSICS_ROOT/tests/sphere.c" "$PHYSICS_SNAPSHOT/sphere.c"
cp "$PHYSICS_ROOT/tests/sphere_swift.swift" "$PHYSICS_SNAPSHOT/sphere_swift.swift"
cp "$PROJECT_ROOT/ios/App/SwiftRapierWorld.swift" "$PHYSICS_SNAPSHOT/SwiftRapierWorld.swift"
cp -R "$PHYSICS_ROOT/include" "$PHYSICS_SNAPSHOT/include"
xcrun clang -Wall -Wextra -Werror -target "$PHYSICS_HOST_TRIPLE" -I "$PHYSICS_SNAPSHOT/include" \
 "$PHYSICS_SNAPSHOT/sphere.c" "$PHYSICS_LIBRARY/libzgtasa_native_physics.a" \
 -framework Security -framework CoreFoundation -liconv -o "$PHYSICS_SNAPSHOT/c-verify"
"$PHYSICS_SNAPSHOT/c-verify"
xcrun swiftc -parse-as-library -whole-module-optimization -Onone -target "$PHYSICS_HOST_TRIPLE" \
 -module-cache-path "$PHYSICS_OUTPUT/modules" -I "$PHYSICS_SNAPSHOT/include" \
 "$PHYSICS_SNAPSHOT/SwiftRapierWorld.swift" "$PHYSICS_SNAPSHOT/sphere_swift.swift" \
 -L "$PHYSICS_LIBRARY" -lzgtasa_native_physics -framework Security -framework CoreFoundation -o "$PHYSICS_SNAPSHOT/swift-verify"
"$PHYSICS_SNAPSHOT/swift-verify"
if [[ -n "${PHYSICS_SPHERE_REFERENCE_DIR:-}" ]]; then
 python3 "$PROJECT_ROOT/tests/movement/smoke_native_sphere_world.py" "$PHYSICS_SPHERE_REFERENCE_DIR"
fi
