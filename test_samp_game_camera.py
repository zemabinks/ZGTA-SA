#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Pure server camera owner regressions; no renderer, network or game assets."""
import json
import pathlib
import subprocess

ROOT=pathlib.Path(__file__).resolve().parent
out=ROOT/'local-only/research/game-camera';out.mkdir(parents=True,exist_ok=True)
binary=out/'camera-tests'
files=['NativeSAMPProtocol.swift','NativeSAMPGameplayCommands.swift','NativeSAMPGameCamera.swift']
r=subprocess.run(['xcrun','swiftc','-O','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',*[str(ROOT/'ios/App'/f) for f in files],str(ROOT/'tests/game_camera/main.swift'),'-o',str(binary)],capture_output=True,text=True)
(out/'build.log').write_text(r.stdout+r.stderr)
if r.returncode:raise SystemExit(f'Compile {r.returncode}\n'+r.stdout+r.stderr)
r=subprocess.run([str(binary)],capture_output=True,text=True,timeout=20)
(out/'stdout.log').write_text(r.stdout);(out/'stderr.log').write_text(r.stderr)
if r.returncode:raise SystemExit(f'Camera test {r.returncode}\n'+r.stdout+r.stderr)
report=json.loads(r.stdout);(out/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');print(json.dumps(report,indent=2,sort_keys=True))
