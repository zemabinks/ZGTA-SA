#!/usr/bin/env python3
"""Native file-management state machine, real synthetic store import and bounded ISO metadata tests."""
from pathlib import Path
import argparse,hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parent
OUT=ROOT/'local-only/research/game-files-107'
SOURCES=['NativeResourceManifest','NativeResourceStore','NativeRawResourceLease','NativeRawResourceStore','NativeGameSourceInspector','NativeGameFilesCoordinator']
WRAPPERS=['NativeISOExtraction','NativeRawResourceSelection']
def both32(n):return n.to_bytes(4,'little')+n.to_bytes(4,'big')
def both16(n):return n.to_bytes(2,'little')+n.to_bytes(2,'big')
def record(name,extent=21,length_bytes=1,directory=False):
 name=name if isinstance(name,bytes) else (name+';1').encode('ascii')
 length=33+len(name)+(len(name)%2==0)
 data=bytearray(length);data[0]=length;data[2:10]=both32(extent);data[10:18]=both32(length_bytes);data[25]=2 if directory else 0;data[28:32]=both16(1);data[32]=len(name);data[33:33+len(name)]=name
 return data
def iso(names):
 data=bytearray(40*2048);pvd=bytearray(2048);pvd[0]=1;pvd[1:6]=b'CD001';pvd[6]=1;pvd[40:72]=b'SYNTHETIC SA SOURCE'.ljust(32,b' ');pvd[80:88]=both32(40);pvd[128:132]=both16(2048);pvd[156:190]=record(b'\x00',20,2048,True);data[16*2048:17*2048]=pvd
 data[17*2048]=255;data[17*2048+1:17*2048+6]=b'CD001';data[17*2048+6]=1
 entries=record(b'\x00',20,2048,True)+record(b'\x01',20,2048,True)
 for name in names:entries+=record(name)
 data[20*2048:20*2048+len(entries)]=entries
 return data
def fixtures(folder):
 cases=[]
 names=['DATA1.HDR','DATA1.CAB','DATA2.CAB','DATA3.CAB','DATA4.CAB']
 def save(name,data,reject=False,candidate=False,count=0):
  (folder/(name+'.iso')).write_bytes(data);cases.append(dict(name=name,reject=reject,candidate=candidate,files=count))
 valid=iso(names);save('valid',valid,candidate=True,count=5)
 save('other',iso(['OTHER.TXT']),count=1)
 save('partial',iso(names[:-1]),count=4)
 save('truncated',valid[:2048],True)
 a=bytearray(valid);a[16*2048+1]=ord('X');save('identifier',a,True)
 a=bytearray(valid);a[16*2048+84]^=1;save('endian',a,True)
 a=bytearray(valid);a[16*2048+128:16*2048+132]=both16(512);save('block-size',a,True)
 a=bytearray(valid);a[16*2048+80:16*2048+88]=both32(1000);save('volume-bounds',a,True)
 a=bytearray(valid);offset=20*2048+68;a[offset+2:offset+10]=both32(1000);save('extent-bounds',a,True)
 a=iso(['../UNSAFE']);save('unsafe-name',a,True)
 a=bytearray(valid);a[20*2048+68+25]|=128;save('multi-extent',a,True)
 a=iso(['DUP.TXT','DUP.TXT']);save('duplicate',a,True)
 a=bytearray(valid);a[20*2048+68:21*2048]=bytes(2048-68);entry=record('CYCLE',20,2048,True);a[20*2048+68:20*2048+68+len(entry)]=entry;save('directory-cycle',a,True)
 (folder/'cases.json').write_text(json.dumps(cases))
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--iso',type=Path,help='Optional owner ISO; read-only metadata inspection, never copied or extracted');args=parser.parse_args()
 OUT.mkdir(parents=True,exist_ok=True)
 checked=subprocess.run(['python3',str(ROOT/'build_installer_bridge.py'),'--check','--platform','host'],capture_output=True,text=True)
 if checked.returncode:subprocess.run(['python3',str(ROOT/'build_installer_bridge.py'),'--platform','host'],check=True)
 paths=[f'ios/App/{name}.swift' for name in SOURCES]+[f'native-installer/swift/{name}.swift' for name in WRAPPERS]+['smoke_native_game_files.swift','smoke_native_game_source.swift','smoke_native_game_files.py']
 captured={path:(ROOT/path).read_bytes() for path in paths};logs=[]
 with tempfile.TemporaryDirectory(prefix='run-',dir=OUT) as temporary:
  work=Path(temporary);isoFolder=work/'iso';isoFolder.mkdir();fixtures(isoFolder)
  for path,data in captured.items():(work/Path(path).name).write_bytes(data)
  def compile_test(test,names,output):
   bridge=['-I',str(ROOT/'native-installer/include'),str(ROOT/'local-only/native-installer/host/libzgtasa_installer.a'),'-lz'] if 'NativeRawResourceStore' in names else []
   result=subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(OUT/'modules'),*[str(work/(name+'.swift')) for name in names],str(work/test),*bridge,'-o',str(work/output)],capture_output=True,text=True)
   (OUT/(output+'-compile.log')).write_text(result.stdout+result.stderr)
   if result.returncode:print(result.stdout+result.stderr);result.check_returncode()
  compile_test('smoke_native_game_files.swift',SOURCES+WRAPPERS,'coordinator')
  run=subprocess.run([str(work/'coordinator'),str(work)],capture_output=True,text=True,timeout=50);logs.append(run.stdout+run.stderr)
  if run.returncode:print(logs[-1]);run.check_returncode()
  compile_test('smoke_native_game_source.swift',['NativeGameSourceInspector'],'inspector')
  command=[str(work/'inspector'),str(isoFolder)]+([str(args.iso)] if args.iso else [])
  run=subprocess.run(command,capture_output=True,text=True,timeout=30);logs.append(run.stdout+run.stderr)
  if (isoFolder/'owner-iso-report.json').exists():(OUT/'owner-iso-report.json').write_bytes((isoFolder/'owner-iso-report.json').read_bytes())
  output=''.join(logs);(OUT/'runtime.log').write_text(output)
  report={'status':'PASS' if run.returncode==0 else 'FAIL','output':output,'sourceHashes':{path:hashlib.sha256(data).hexdigest() for path,data in captured.items()},'liveSourcesStillMatch':{path:(ROOT/path).read_bytes()==data for path,data in captured.items()},'ownerISOReadOnly':bool(args.iso),'limits':['Injected store-service state machine plus actual production store/adapter against invented bootstrap/resource bytes; no real game rendering claim','ISO test reads directory metadata only; filenames do not verify edition or imply extraction, conversion or installation','No UIKit runtime, physical device, browser, saves or production server operated']}
  (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(output,end='');run.check_returncode()
if __name__=='__main__':main()
