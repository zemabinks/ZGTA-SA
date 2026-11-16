#!/bin/zsh
set -euo pipefail
PHYSICS_ROOT="${0:A:h}"
PROJECT_ROOT="${PHYSICS_ROOT:h}"
PHYSICS_OUTPUT="$PROJECT_ROOT/local-only/native-physics"
case "$(uname -m)" in
  arm64) PHYSICS_LIB="$PHYSICS_OUTPUT/macos-arm64"; PHYSICS_TRIPLE=arm64-apple-macosx13.0 ;;
  x86_64) PHYSICS_LIB="$PHYSICS_OUTPUT/macos-x86_64"; PHYSICS_TRIPLE=x86_64-apple-macosx13.0 ;;
  *) exit 2 ;;
esac
python3 "$PHYSICS_ROOT/source_stamp.py" check "$PHYSICS_LIB"
mkdir -p "$PHYSICS_OUTPUT/tests/joints"
cp "$PROJECT_ROOT/ios/App/SwiftRapierWorld.swift" "$PHYSICS_OUTPUT/tests/joints/"
python3 - "$PROJECT_ROOT" "$PHYSICS_LIB" <<'PY'
import hashlib,json,sys
from pathlib import Path
root,library=map(Path,sys.argv[1:])
paths=[root/'ios/App/SwiftRapierWorld.swift',root/'native-physics/tests/joints.c',root/'native-physics/tests/joints_fixture.js',root/'native-physics/tests/joints/main.swift',root/'native-physics/test_joints.sh',root/'native-physics/include/ZGTARapier.h',library/'libzgtasa_native_physics.a',library/'source-stamp.json']
record={'inputs':{str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in paths},'librarySourceStamp':json.loads((library/'source-stamp.json').read_text()),'note':'Actual source-stamped host library; archived WASM measurements remain private.'}
(root/'local-only/native-physics/tests/joints/source-hashes.json').write_text(json.dumps(record,indent=2)+'\n')
PY
xcrun clang -target "$PHYSICS_TRIPLE" -I "$PHYSICS_ROOT/include" "$PHYSICS_ROOT/tests/joints.c" "$PHYSICS_LIB/libzgtasa_native_physics.a" -framework Security -framework CoreFoundation -liconv -o "$PHYSICS_OUTPUT/tests/joints/c-verify"
"$PHYSICS_OUTPUT/tests/joints/c-verify"
node "$PHYSICS_ROOT/tests/joints_fixture.js"
xcrun swiftc -target "$PHYSICS_TRIPLE" -module-cache-path "$PHYSICS_OUTPUT/swift-module-cache" -I "$PHYSICS_ROOT/include" "$PHYSICS_OUTPUT/tests/joints/SwiftRapierWorld.swift" "$PHYSICS_ROOT/tests/joints/main.swift" -L "$PHYSICS_LIB" -lzgtasa_native_physics -framework Security -framework CoreFoundation -o "$PHYSICS_OUTPUT/tests/joints/swift-verify"
"$PHYSICS_OUTPUT/tests/joints/swift-verify" "$PROJECT_ROOT/local-only/physics-fixtures/spherical-joints.json" "$PHYSICS_OUTPUT/tests/joints/report.json"
python3 "$PHYSICS_ROOT/source_stamp.py" check "$PHYSICS_LIB"
python3 - "$PROJECT_ROOT" <<'PY'
import hashlib,json,sys
from pathlib import Path
root=Path(sys.argv[1]);file=root/'local-only/native-physics/tests/joints/source-hashes.json';record=json.loads(file.read_text())
record['sourcesUnchanged']=all(hashlib.sha256(Path(path).read_bytes()).hexdigest()==digest for path,digest in record['inputs'].items())
record['measurements']={str(path.relative_to(root)):hashlib.sha256(path.read_bytes()).hexdigest() for path in [root/'local-only/physics-fixtures/spherical-joints.json',root/'local-only/native-physics/tests/joints/report.json']}
file.write_text(json.dumps(record,indent=2)+'\n')
assert record['sourcesUnchanged'],'Joint production/test inputs changed during this run'
print('PASS joint provenance: all production/test inputs and source-stamped library unchanged')
PY
