#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual projectile clock under unavailable streamed geometry; asset-free."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse,subprocess,json,hashlib,time
root=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--historical-root',type=Path);args=parser.parse_args()
out=root/'local-only/research/projectile-clock-117'/str(time.time_ns());out.mkdir(parents=True)
fixture=(root/'tests/hosting/smoke_native_projectile_clock.swift').read_bytes()
results=[]
for label,base in [('current',root)]+([('historical',args.historical_root.resolve())]if args.historical_root else []):
 work=out/label;work.mkdir();raw=(base/'ios/App/NativeWeaponEffects.swift').read_bytes()
 model=work/'NativeWeaponEffects.swift';model.write_bytes(raw);main=work/'main.swift';main.write_bytes(fixture)
 command=['xcrun','swiftc','-swift-version','5','-whole-module-optimization','-Onone','-num-threads','1','-module-cache-path',str(out/'modules'),str(model),str(main),'-o',str(work/'verify')]
 with (work/'compile.log').open('w')as log:p=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=180)
 if p.returncode:print((work/'compile.log').read_text()[-6000:]);p.check_returncode()
 p=subprocess.run([str(work/'verify')],text=True,capture_output=True,timeout=30);(work/'runtime.log').write_text(p.stdout+p.stderr)
 if label=='current':print(p.stdout,end='');p.check_returncode()
 else:assert p.returncode==23 and 'unknown coverage cannot freeze projectile age' in p.stderr,'Historical control must compile and fail target assertion'
 assert raw==(base/'ios/App/NativeWeaponEffects.swift').read_bytes()
 results.append({'label':label,'sourceSHA256':hashlib.sha256(raw).hexdigest(),'exitCode':p.returncode,'output':p.stdout+p.stderr})
assert fixture==(root/'tests/hosting/smoke_native_projectile_clock.swift').read_bytes()
(out/'report.json').write_text(json.dumps({'pass':True,'results':results,'sourceUnchanged':True,'fixtureSHA256':hashlib.sha256(fixture).hexdigest(),'scope':'Actual helper, authored snapshots, explicit coverage/ray callbacks; no socket, GPU, server damage or retail runtime'},indent=2)+'\n')
print('Report:',out/'report.json')
