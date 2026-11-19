#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Production C traversal against real descriptors and authored alias failures."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[2]

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--historical-root',type=Path);a=p.parse_args();os.setpriority(os.PRIO_PROCESS,0,15)
 out=ROOT/'local-only/research/raw-directory-case-130'/str(time.time_ns());out.mkdir(parents=True)
 subprocess.run(['python3','build_installer_bridge.py','--platform','host','--check'],cwd=ROOT,check=True)
 archive=ROOT/'local-only/native-installer/host/libzgtasa_installer.a';stamp=json.loads((archive.parent/'source-stamp.json').read_text());sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest();assert sha(archive)==stamp['librarySHA256']
 paths=[ROOT/'native-installer/src/zgtasa_installer.c',ROOT/'tests/resources/smoke_native_raw_directory_case.c',Path(__file__).resolve(),archive]
 variants=([('historical',a.historical_root.resolve())] if a.historical_root else [])+[('current',ROOT)]
 if a.historical_root:paths.append(a.historical_root/'native-installer/src/zgtasa_installer.c')
 frozen={str(path):sha(path)for path in paths};results=[]
 for label,source in variants:
  work=out/label;work.mkdir();(work/'production.c').write_bytes((source/'native-installer/src/zgtasa_installer.c').read_bytes());(work/'Gate.c').write_bytes((ROOT/'tests/resources/smoke_native_raw_directory_case.c').read_bytes())
  (work/'libunshield_export.h').write_text('#define UNSHIELD_API\n')
  command=['xcrun','clang','-std=c11','-O1','-g','-fsanitize=address,undefined','-fno-sanitize-recover=all','-fno-omit-frame-pointer','-I'+str(ROOT/'native-installer/include'),'-I'+str(ROOT/'native-installer/vendor/unshield/lib'),'-I'+str(work),str(work/'Gate.c'),str(archive),'-lz','-o',str(work/'verify')]
  if label=='historical':command.insert(2,'-DHISTORICAL=1')
  start=time.monotonic();built=subprocess.run(command,capture_output=True,text=True,timeout=180);(work/'compile.log').write_text(built.stdout+built.stderr);built.check_returncode()
  result=subprocess.run([str(work/'verify'),str(work/'authored-root')],capture_output=True,text=True,timeout=30);(work/'runtime.log').write_text(result.stdout+result.stderr)
  row={'label':label,'exitCode':result.returncode,'seconds':time.monotonic()-start,'output':result.stdout+result.stderr,'sanitizers':['address','undefined']};results.append(row)
  if label=='historical':assert result.returncode==2 and 'existing case alias was rejected' in row['output'],row
  else:assert result.returncode==0 and 'PASS' in row['output'],row
 assert all(sha(Path(path))==value for path,value in frozen.items())
 report={'status':'PASS','results':results,'sourceUnchanged':True,'sourceHashes':frozen,'scope':'Actual production C traversal; real FDs and authored syscall/enumeration failure carriers. No original resources, UIKit, GPU, live importer or retail claim.'};(out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'status':'PASS','results':results,'output':str(out)},indent=2))
if __name__=='__main__':main()
