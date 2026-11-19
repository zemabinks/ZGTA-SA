#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Authored WRL2 footer/layout checks; no game files, GPU or UI."""
from pathlib import Path
import hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]
def main():
 out=ROOT/'local-only/research/world-sharp-146/layout'/str(time.time_ns());out.mkdir(parents=True)
 files=[ROOT/'ios/App/WorldBinary.swift',ROOT/'ios/App/NativeWorldSharpLayout.swift',ROOT/'ios/App/NativeWorldSharpManifest.swift',ROOT/'ios/App/NativeWorldSharpWork.swift',Path(__file__).with_suffix('.swift')]
 before={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()for p in files}
 command=['xcrun','swiftc','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),*map(str,files),'-o',str(out/'probe')]
 with(out/'compile.log').open('w')as log:r=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=180)
 if r.returncode:print((out/'compile.log').read_text()[-5000:]);r.check_returncode()
 r=subprocess.run([str(out/'probe')],text=True,capture_output=True,timeout=30);(out/'runtime.log').write_text(r.stdout+r.stderr)
 report=dict(status='PASS'if r.returncode==0 else'FAIL',exitCode=r.returncode,output=r.stdout+r.stderr,sourceUnchanged=all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h for n,h in before.items()),sourceHashes=before,worldResourceOrGPUUsed=False)
 (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out.parent/'latest.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report));r.check_returncode();assert report['sourceUnchanged']
if __name__=='__main__':main()
