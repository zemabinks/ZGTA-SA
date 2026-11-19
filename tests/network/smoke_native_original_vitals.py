#!/usr/bin/env python3
"""Actual archived fractional vitals/effects against the independent native owner."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
def main():
    out=ROOT/'local-only/research/original-world-vitals';out.mkdir(parents=True,exist_ok=True)
    paths=['ios/App/NativeOriginalWorldVitals.swift','ios/App/NativeOriginalWorldEffects.swift','tests/network/smoke_native_original_vitals.js','tests/network/smoke_native_original_vitals.swift','tests/network/smoke_native_original_vitals.py']
    before={name:(ROOT/name).read_bytes()for name in paths}
    subprocess.run(['node',str(ROOT/'tests/network/smoke_native_original_vitals.js'),str(out/'goldens.json')],check=True)
    with tempfile.TemporaryDirectory(prefix='snapshot-',dir=out)as temporary:
        work=Path(temporary);(work/'vitals.swift').write_bytes(before['ios/App/NativeOriginalWorldVitals.swift']);(work/'effects.swift').write_bytes(before['ios/App/NativeOriginalWorldEffects.swift']);(work/'main.swift').write_bytes(before['tests/network/smoke_native_original_vitals.swift'])
        result=subprocess.run(['xcrun','swiftc','-Onone','-module-cache-path',str(out/'modules'),str(work/'vitals.swift'),str(work/'effects.swift'),str(work/'main.swift'),'-o',str(work/'verify')],capture_output=True,text=True);(out/'compile.log').write_text(result.stdout+result.stderr)
        if result.returncode:print(result.stdout+result.stderr);result.check_returncode()
        result=subprocess.run([str(work/'verify'),str(out/'goldens.json')],capture_output=True,text=True);unchanged=all((ROOT/name).read_bytes()==data for name,data in before.items())
        golden=json.loads((out/'goldens.json').read_text())
        report={'status':'PASS'if result.returncode==0 and unchanged else'FAIL','sourceUnchanged':unchanged,'sourceHashes':{name:hashlib.sha256(data).hexdigest()for name,data in before.items()},'archivedSHA256':golden['sourceSHA256'],'expressionsSHA256':golden['expressionsSHA256'],'cases':len(golden['cases']),'fatalAdmissionCases':len(golden['fatalCases']),'effectTimerCases':len(golden['effects']),'output':result.stdout+result.stderr,'limits':['Actual archived hurt/setter/godly/respawn methods with controlled effect/animation callbacks','Actual archived onShot fatal admission/deadline tested with controlled occupied vehicle owner; rendered exit remains separate','Deferred fatal identity/ready/consume checks are native ownership regressions, not rendered exit acceptance','No authenticated original-site native gameplay, retail1:1 or physical-device performance claim']}
        (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged
if __name__=='__main__':main()
