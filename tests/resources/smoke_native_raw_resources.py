#!/usr/bin/env python3
"""Native raw-stage/coordinator regressions. All data/results stay owner-local."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,subprocess,tempfile,os
from tests.resources.native_raw_test_support import pinned_host_archive
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/research/raw-resource-compat'
NAMES=['NativeResourceManifest','NativeResourceStore','NativeRawResourceLease','NativeRawResourceStore','NativeGameSourceInspector','NativeGameFilesCoordinator']
def main():
 OUT.mkdir(parents=True,exist_ok=True)
 library=pinned_host_archive(os.environ.get('ZGTA_RAW_TEST_ARCHIVE'))
 paths=[ROOT/'ios/App'/str(n+'.swift') for n in NAMES]+[ROOT/'native-installer/swift/NativeISOExtraction.swift',ROOT/'native-installer/swift/NativeRawResourceSelection.swift',ROOT/'tests/resources/smoke_native_raw_resources.swift',Path(__file__),ROOT/'tests/resources/native_raw_test_support.py']
 captured={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
 with tempfile.TemporaryDirectory(prefix='run-',dir=OUT) as folder:
  work=Path(folder);sources=[]
  for path in paths:
   if path.suffix=='.swift':copy=work/path.name;copy.write_bytes(path.read_bytes());sources.append(copy)
  command=['xcrun','swiftc','-parse-as-library','-I',str(ROOT/'native-installer/include'),'-module-cache-path',str(OUT/'modules'),*map(str,sources),str(library),'-lz','-o',str(work/'raw')]
  run=subprocess.run(command,capture_output=True,text=True);(OUT/'compile.log').write_text(run.stdout+run.stderr)
  if run.returncode:print(run.stdout+run.stderr);run.check_returncode()
  command=[str(work/'raw'),str(work)]
  run=subprocess.run(command,capture_output=True,text=True,timeout=240);output=run.stdout+run.stderr;(OUT/'runtime.log').write_text(output)
  report={'status':'PASS' if run.returncode==0 else 'FAIL','fixtures':'Independently authored source/resource bytes only','output':output,'sourceHashes':captured,'liveSourcesStillMatch':all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==sha for p,sha in captured.items()),'limits':['Injected authored raw sources for lifecycle negatives; actual C metadata refusal uses an invented malformed source','The App default uses its actual ISO extractor, never the authored fixture extractor','No UIKit/Files provider/device/UI/performance/native-conversion or playable-installation acceptance']}
  (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(output,end='');run.check_returncode()
if __name__=='__main__':main()
