#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Camera source/retry ownership through production transport and queued delivery."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--historical-root', type=Path)
    args = parser.parse_args()
    source = (args.historical_root or ROOT).resolve()
    out = ROOT / 'local-only/research/camera-source-153' / str(time.time_ns())
    out.mkdir(parents=True)
    paths = [source / 'ios/App' / (n + '.swift') for n in ['ServerAddress', 'NativeGameCamera']]
    paths += [Path(__file__).with_suffix('.swift')]
    frozen = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [*paths, Path(__file__)]}
    command = ['xcrun', 'swiftc', '-j', '1', '-whole-module-optimization', '-num-threads', '1', '-Onone',
               '-module-cache-path', str(out / 'modules'), *map(str, paths), '-o', str(out / 'camera-source')]
    with (out / 'compile.log').open('x') as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=300)
    if result.returncode:
        print((out / 'compile.log').read_text()[-4000:]); result.check_returncode()
    result = subprocess.run([str(out / 'camera-source')], capture_output=True, text=True, timeout=60)
    (out / 'runtime.log').write_text(result.stdout + result.stderr)
    report = dict(status='PASS' if result.returncode == 0 else 'FAIL', exitCode=result.returncode,
                  sourceHashes=frozen, sourcesHeld=all(hashlib.sha256(Path(p).read_bytes()).hexdigest() == h for p, h in frozen.items()),
                  historical=bool(args.historical_root), output=result.stdout + result.stderr,
                  scope='Actual camera/transport sources; authored configurations and controlled completion delivery; no HTTP, UI, device or original-retail timing acceptance')
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    (out.parent / 'latest.json').write_text(json.dumps(dict(path=str(out), **report), indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ['status', 'exitCode', 'sourcesHeld', 'historical']}), str(out))
    print((result.stdout + result.stderr)[:2000]); result.check_returncode(); assert report['sourcesHeld']


if __name__ == '__main__':
    main()
