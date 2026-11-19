#!/usr/bin/env python3
"""Actual Apple C/Swift direct-ISO extraction bridge; original resources stay local."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse,hashlib,json,subprocess,tempfile,struct
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/research/native-installer-107'
def number(value):return struct.pack('<I',value)+struct.pack('>I',value)
def record(name,block,size,directory=False):
 name=name if isinstance(name,bytes) else (name+';1').encode('ascii');length=33+len(name)+(len(name)%2==0)
 out=bytearray(length);out[0]=length;out[2:10]=number(block);out[10:18]=number(size);out[25]=2 if directory else 0;out[28:32]=b'\x01\0\0\x01';out[32]=len(name);out[33:33+len(name)]=name;return out
def thin_iso(header):
 blocks=24+(len(header)+2047)//2048+5;out=bytearray(blocks*2048);p=bytearray(2048);p[0]=1;p[1:6]=b'CD001';p[6]=1;p[80:88]=number(blocks);p[128:132]=b'\0\x08\x08\0';p[156:190]=record(b'\0',20,2048,True);out[16*2048:17*2048]=p;out[17*2048]=255;out[17*2048+1:17*2048+6]=b'CD001';out[17*2048+6]=1
 entries=record(b'\0',20,2048,True)+record(b'\1',20,2048,True);entries+=record('DATA1.HDR',21,len(header));out[21*2048:21*2048+len(header)]=header
 first_cab=22+(len(header)+2047)//2048
 for i in range(4):
  block=first_cab+i;entries+=record(f'DATA{i+1}.CAB',block,84)
  if len(header)>=8:out[block*2048:block*2048+8]=header[:8]
 out[20*2048:20*2048+len(entries)]=entries;return out
def owner_member(iso,path):
 with iso.open('rb') as file:
  file.seek(16*2048);primary=file.read(2048)
  extent=struct.unpack_from('<I',primary,158)[0];size=struct.unpack_from('<I',primary,166)[0]
  for part in path.split('/'):
   assert size<=4*1024*1024
   file.seek(extent*2048);directory=file.read(size);at=0;found=None
   while at<len(directory):
    length=directory[at]
    if not length:at=(at//2048+1)*2048;continue
    name=directory[at+33:at+33+directory[at+32]].split(b';')[0]
    if name.upper()==part.encode().upper():found=(struct.unpack_from('<I',directory,at+2)[0],struct.unpack_from('<I',directory,at+10)[0]);break
    at+=length
   assert found is not None,path;extent,size=found
  assert size<=8*1024*1024
  file.seek(extent*2048);result=file.read(size);assert len(result)==size;return result
def source_header(iso):
 with iso.open('rb') as file:
  file.seek(16*2048);p=file.read(2048);assert p[1:6]==b'CD001'
  block=struct.unpack_from('<I',p,158)[0];size=struct.unpack_from('<I',p,166)[0];assert size<=4*1024*1024
  file.seek(block*2048);directory=file.read(size);at=0
  while at<len(directory):
   length=directory[at]
   if not length:at=(at//2048+1)*2048;continue
   name=directory[at+33:at+33+directory[at+32]].split(b';')[0]
   if name.upper()==b'DATA1.HDR':
    extent=struct.unpack_from('<I',directory,at+2)[0];size=struct.unpack_from('<I',directory,at+10)[0];assert 20<=size<=32*1024*1024
    file.seek(extent*2048);data=file.read(size);assert len(data)==size;return data
   at+=length
 raise AssertionError('Owner ISO header not found')
def malformed_fixtures(folder,iso):
 original=source_header(iso);descriptor=struct.unpack_from('<I',original,12)[0];table=descriptor+struct.unpack_from('<I',original,descriptor+12)[0];second=struct.unpack_from('<I',original,descriptor+44)[0];count=struct.unpack_from('<I',original,descriptor+40)[0];cases=[]
 def save(name,header):(folder/(name+'.iso')).write_bytes(thin_iso(header));cases.append(name)
 save('header-short',original[:20])
 data=bytearray(original);struct.pack_into('<I',data,descriptor+40,0xffffffff);save('file-count',data)
 data=bytearray(original);struct.pack_into('<I',data,table,0xffffffff);save('directory-string',data)
 data=bytearray(original);struct.pack_into('<I',data,table+second+61*87+58,0xffffffff);save('filename-string',data)
 data=bytearray(original);data[table+second+61*87+84]|=1;struct.pack_into('<I',data,table+second+61*87+76,61);save('member-link-cycle',data)
 group_head=next(struct.unpack_from('<I',original,descriptor+0x3e+i*4)[0] for i in range(71) if struct.unpack_from('<I',original,descriptor+0x3e+i*4)[0])
 data=bytearray(original);struct.pack_into('<I',data,descriptor+group_head+8,group_head);save('group-cycle',data)
 group=descriptor+struct.unpack_from('<I',original,descriptor+group_head+4)[0]
 data=bytearray(original);struct.pack_into('<I',data,group+26,count+1);save('group-range',data)
 data=bytearray(original);struct.pack_into('<I',data,4,900);save('unsupported-version-class',data)
 (folder/'malformed-cases.json').write_text(json.dumps(cases));(folder/'truncated-cabinets.iso').write_bytes(thin_iso(original))
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--iso',type=Path);parser.add_argument('--accepted-root',type=Path,help='Existing accepted selected original resources; read-only');args=parser.parse_args()
 if bool(args.iso)!=bool(args.accepted_root):parser.error('--iso and --accepted-root must be provided together')
 OUT.mkdir(parents=True,exist_ok=True);subprocess.run(['python3',str(ROOT/'build_installer_bridge.py'),'--platform','host'],check=True)
 paths=[p for p in (ROOT/'native-installer').rglob('*') if p.is_file()]+[ROOT/'build_installer_bridge.py',Path(__file__)]
 captured={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
 with tempfile.TemporaryDirectory(prefix='run-',dir=OUT) as temporary:
  work=Path(temporary)
  if args.iso:
   malformed_fixtures(work,args.iso)
   (work/'expected-radio-AA').write_bytes(owner_member(args.iso,'AUDIO/STREAMS/AA'))
  executable=work/'smoke';sources=[ROOT/'native-installer/swift/NativeRawResourceSelection.swift',ROOT/'native-installer/swift/NativeISOExtraction.swift',ROOT/'native-installer/tests/main.swift']
  run=subprocess.run(['xcrun','swiftc','-parse-as-library','-I',str(ROOT/'native-installer/include'),*map(str,sources),str(ROOT/'local-only/native-installer/host/libzgtasa_installer.a'),'-lz','-module-cache-path',str(OUT/'swift-modules'),'-o',str(executable)],capture_output=True,text=True)
  (OUT/'compile.log').write_text(run.stdout+run.stderr)
  if run.returncode:print(run.stdout+run.stderr);run.check_returncode()
  command=[str(executable),str(work.resolve())]+([str(args.iso),str(args.accepted_root)] if args.iso else [])
  run=subprocess.run(command,capture_output=True,text=True,timeout=60);output=run.stdout+run.stderr;(OUT/'runtime.log').write_text(output)
  if (work/'owner-report.json').exists():(OUT/'owner-report.json').write_bytes((work/'owner-report.json').read_bytes())
  report={'status':'PASS' if run.returncode==0 else 'FAIL','output':output,'sourceHashes':captured,'liveSourcesStillMatch':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==digest for p,digest in captured.items()},'actualOwnerISO':bool(args.iso),'limits':['Host C/Swift execution; iOS/simulator cross-compilation is separate from device runtime','Original metadata/data fixtures and extracted test bytes remain local-only','Raw resources retained do not establish native converter coverage or a playable installation']}
  (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(output,end='');run.check_returncode()
if __name__=='__main__':main()
