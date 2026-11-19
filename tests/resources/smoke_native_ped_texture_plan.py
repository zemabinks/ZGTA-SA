#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Pure native texture planning against authored meshes; no game files or GPU."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
out=ROOT/'local-only/research/ped-texture-plan-143'
out.mkdir(parents=True,exist_ok=True)
paths=[ROOT/'ios/App'/name for name in ['WorldBinary.swift','NativePedAtlasLayout.swift']]+[Path(__file__).with_suffix('.swift'),Path(__file__)]
captured={p:p.read_bytes() for p in paths}
with tempfile.TemporaryDirectory(prefix='run-',dir=out) as folder:
    work=Path(folder)
    for p,data in captured.items():(work/p.name).write_bytes(data)
    commands=[['xcrun','swiftc','-parse-as-library','-swift-version','5','-j','1','-num-threads','1','-module-cache-path',str(out/'modules'),
               *[str(work/p.name) for p in paths if p.suffix=='.swift'],'-o',str(work/'gate')],[str(work/'gate')]]
    results=[]
    for label,command in zip(['compile','runtime'],commands):
        result=subprocess.run(command,capture_output=True,text=True,timeout=180)
        (out/(label+'.log')).write_text(result.stdout+result.stderr)
        results.append(dict(stage=label,exitCode=result.returncode))
        if result.returncode:print(result.stdout+result.stderr);break
    unchanged=all(p.read_bytes()==data for p,data in captured.items())
    report=dict(status='PASS' if len(results)==2 and unchanged and all(r['exitCode']==0 for r in results) else 'FAIL',
                results=results,sourceUnchanged=unchanged,sourceHashes={str(p):hashlib.sha256(data).hexdigest() for p,data in captured.items()},originalAssetsUsed=False)
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
    if report['status']!='PASS':raise SystemExit(1)
