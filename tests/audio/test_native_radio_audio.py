#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Independent authored compressed-radio regression; no game data or services."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse,hashlib,importlib.util,json,math,os,platform,struct,subprocess,sys,time
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('radio_build',ROOT/'native-audio/build.py');build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build)
sys.path.insert(0,str(ROOT/'native-audio/tests'));import fixtures
KEY=bytes([234,58,196,161,154,168,20,243,72,176,215,35,157,232,255,241]);HEADER=8068

def crc(data):
 value=0
 for b in data:
  value^=b<<24
  for _ in range(8):value=((value<<1)^(0x04c11db7 if value&0x80000000 else 0))&0xffffffff
 return value

def page(serial,seq,flags,granule,body):
 laces=bytes([255]*(len(body)//255)+[len(body)%255]);assert len(laces)<=255
 head=bytearray(b'OggS'+bytes([0,flags])+struct.pack('<QII',granule,serial,seq)+b'\0'*4+bytes([len(laces)])+laces+body);struct.pack_into('<I',head,22,crc(head));return bytes(head)

def recalc_first(data):
 b=bytearray(data);size=27+b[26]+sum(b[27:27+b[26]]);b[22:26]=b'\0'*4;struct.pack_into('<I',b,22,crc(b[:size]));return bytes(b)

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--all-platforms',action='store_true');parser.add_argument('--sanitize',action='store_true');parser.add_argument('--output',type=Path);parser.add_argument('--library-root',type=Path);parser.add_argument('--sanitized-library-root',type=Path);args=parser.parse_args()
 if args.sanitized_library_root is not None and not args.sanitize:parser.error('--sanitized-library-root requires --sanitize')
 out=build.private_output(args.output or ROOT/'local-only/research'/('native-radio-tests-'+str(time.time_ns())));out.mkdir(parents=True)
 src=[ROOT/'ios/App/NativeRadioArchive.swift',ROOT/'tests/audio/test_native_radio_audio.py',*sorted((ROOT/'native-audio/tests').glob('*'))];src=[p for p in src if p.is_file()];before={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()for p in src};before.update({'native-audio/'+k:v for k,v in build.source_hashes().items()})
 report={'scope':'Actual C ABI/Swift parser with authored mathematical Vorbis fixtures; no original audio, server, iOS runtime or playback claim','checks':[],'work':str(out)}
 def check(value,label):
  report['checks'].append({'label':label,'passed':bool(value)})
  if not value:raise AssertionError(label)
 def run(command,name,timeout=240):
  environment={**os.environ,'UBSAN_OPTIONS':'halt_on_error=1:print_stacktrace=1','ASAN_OPTIONS':'halt_on_error=1'}
  try:r=subprocess.run(list(map(str,command)),cwd=ROOT,capture_output=True,timeout=timeout,env=environment)
  except subprocess.TimeoutExpired as e:(out/(name+'.log')).write_bytes((e.stdout or b'')+(e.stderr or b''));raise
  (out/(name+'.log')).write_bytes(r.stdout+r.stderr);check(r.returncode==0,name);return r
 def pack(name,data,offset=29):
  start=offset+HEADER;p=out/(name+'.bin');p.write_bytes(bytes(start)+bytes(b^KEY[(start+i)&15]for i,b in enumerate(data))+b'outside-record-never-read');return p,offset,HEADER+len(data)
 try:
  libraries=build.private_output(args.library_root) if args.library_root else out/'build'
  if args.library_root is None:
   command=[sys.executable,ROOT/'native-audio/build.py','--platform','all'if args.all_platforms else'host','--output',libraries];run(command,'build',1200)
  host='macos-arm64'if platform.machine()=='arm64'else'macos-x86_64'
  expected_sources=build.source_hashes();expected_stamp=hashlib.sha256(json.dumps(expected_sources,sort_keys=True,separators=(',',':')).encode()).hexdigest()
  for name in list(build.TARGETS)if args.all_platforms else[host]:
   folder=libraries/name;build.private_output(folder)
   metadata=json.loads((folder/'source-stamp.json').read_text())
   check(metadata['sourceHashes']==expected_sources and metadata['sourceStamp']==expected_stamp and metadata['target']==build.TARGETS[name][1] and metadata['sanitizers']==False,'exact-library-sources-'+name)
   for artifact,key in [('libzgtasa_native_audio.a','librarySHA256'),('link-probe','linkProbeSHA256')]:
    path=folder/artifact;check(not path.is_symlink()and path.is_file()and hashlib.sha256(path.read_bytes()).hexdigest()==metadata[key],'exact-library-artifact-'+name+'-'+artifact)
  library=libraries/host/'libzgtasa_native_audio.a'
  stamp=json.loads((library.parent/'source-stamp.json').read_text())['sourceStamp']
  for name in ['window','api']:
   run(['xcrun','clang','-std=gnu11','-O2','-DEXPECTED_SOURCE_STAMP="'+stamp+'"','-I',ROOT/'native-audio/include',ROOT/('native-audio/tests/'+name+'.c'),library,'-lm','-o',out/name],'compile-'+name)
  def window(item,first,count,expect=0,exe=None):
   p,offset,length=item;r=subprocess.run([str(exe or out/'window'),str(p),str(offset),str(length),str(first),str(count)],capture_output=True,timeout=20,env={**os.environ,'UBSAN_OPTIONS':'halt_on_error=1:print_stacktrace=1','ASAN_OPTIONS':'halt_on_error=1'})
   if expect:
    check(r.returncode!=0,'reject-'+p.stem);s=json.loads(r.stderr);check(s['status']==expect,'exact-status-'+p.stem)
    if expect==12:check(s['heapBytes']==0 and s['peakHeapBytes']<=16*1024*1024,'budget-abort-releases-codec-allocations')
    return
   check(r.returncode==0,'window-'+p.stem)
   info=struct.unpack('<5Q',r.stdout[:40]);samples=struct.unpack('<'+str((len(r.stdout)-40)//4)+'f',r.stdout[40:]);check(info[4]*2==len(samples),'bounded-output-'+p.stem);check(all(math.isfinite(x)for x in samples),'finite-'+p.stem);return info,samples
  valid={}
  for name in ['stereo','mono']:
   item=pack(name,fixtures.payload(name),29 if name=='stereo' else 43);valid[name]=item
   for first in [0,1,15,255,7000,7999,8000,15996,16000]:
    info,samples=window(item,first,min(8000,16000-first) or 1);check(info[:4]==(16000,32000,fixtures.FIXTURES[name]['channels'],2),'format-'+name)
    for index,expected in fixtures.FIXTURES[name]['reference'].items():
     frame=int(index)-first
     if 0<=frame<info[4]:
      wanted=expected if len(expected)==2 else expected*2
      check(max(abs(samples[frame*2+j]-wanted[j])for j in range(2))<5e-6,'independent-PCM-'+name+'-'+index)
  run([out/'api',valid['stereo'][0],valid['stereo'][2],valid['stereo'][1],out],'api')
  stereo=fixtures.payload('stereo')
  bad=bytearray(stereo);bad[100]^=1;window(pack('bad-crc',bad),0,1,5)
  window(pack('truncated',stereo[:-1]),0,1,5);window(pack('trailing',stereo+b'\0'),0,1,5);window(pack('chained',stereo+fixtures.payload('mono')),0,1,5)
  header=27+stereo[26]
  bad=bytearray(stereo);struct.pack_into('<I',bad,header+12,44100);window(pack('wrong-rate',recalc_first(bad)),0,1,6)
  bad=bytearray(stereo);bad[header+11]=3;window(pack('wrong-channels',recalc_first(bad)),0,1,6)
  bad=bytearray(stereo);bad[18]=1;window(pack('wrong-sequence',recalc_first(bad)),0,1,5)
  # Tiny malicious setup requests a huge ordered codebook. Allocator guard must
  # escape safely before unmodified upstream code could dereference NULL.
  bits=[]
  for value,n in [(0,8),(0x564342,24),(0,16),(16777215,24),(1,1),(0,5)]:bits.extend((value>>i)&1 for i in range(n))
  setup=b'\x05vorbis'+bytes(sum(bits[i+j]<<j for j in range(min(8,len(bits)-i)))for i in range(0,len(bits),8))
  comment=b'\x03vorbis'+struct.pack('<II',0,0)+b'\x01';ident=stereo[header:header+30]
  bomb=b''.join([page(17,0,2,0,ident),page(17,1,0,0,comment),page(17,2,0,0,setup),page(17,3,4,1,b'\x00')])
  window(pack('allocation-budget',bomb),0,1,12)
  # Actual Swift catalogue/descriptor source, no substitute model.
  run(['xcrun','swiftc','-parse-as-library','-whole-module-optimization','-Onone','-module-cache-path',out/'swift-modules',ROOT/'ios/App/NativeRadioArchive.swift',ROOT/'native-audio/tests/archive.swift','-o',out/'archive-tests'],'compile-swift')
  run([out/'archive-tests',out/'swift-fixtures'],'swift-archive')
  # Reject linked output before compiling/writing, while retaining its target.
  target=out/'unrelated-output';target.mkdir();(target/'keep.txt').write_text('authored keep');link=out/'linked-output';link.symlink_to(target,target_is_directory=True)
  rejected=subprocess.run([sys.executable,str(ROOT/'native-audio/build.py'),'--output',str(link)],capture_output=True);check(rejected.returncode!=0 and (target/'keep.txt').read_text()=='authored keep'and len(list(target.iterdir()))==1,'reject-linked-output')
  if args.sanitize:
   sanitized_root=build.private_output(args.sanitized_library_root) if args.sanitized_library_root is not None else out/'sanitize'
   if args.sanitized_library_root is None:
    run([sys.executable,ROOT/'native-audio/build.py','--platform','host','--sanitize','--output',sanitized_root],'build-sanitized',1200)
   folder=sanitized_root/host;metadata=json.loads((folder/'source-stamp.json').read_text())
   check(metadata['sourceHashes']==expected_sources and metadata['sourceStamp']==expected_stamp and metadata['target']==build.TARGETS[host][1] and metadata['sanitizers'] is True,'exact-sanitized-library-sources')
   for artifact,key in [('libzgtasa_native_audio.a','librarySHA256'),('link-probe','linkProbeSHA256')]:
    path=folder/artifact;check(not path.is_symlink()and path.is_file()and hashlib.sha256(path.read_bytes()).hexdigest()==metadata[key],'exact-sanitized-library-artifact-'+artifact)
   lib=folder/'libzgtasa_native_audio.a'
   sanitized_stamp=metadata['sourceStamp']
   for name in ['window','api']:
    run(['xcrun','clang','-std=gnu11','-O1','-g','-DEXPECTED_SOURCE_STAMP="'+sanitized_stamp+'"','-fsanitize=address,undefined','-fno-omit-frame-pointer','-I',ROOT/'native-audio/include',ROOT/('native-audio/tests/'+name+'.c'),lib,'-lm','-o',out/(name+'-sanitized')],'compile-'+name+'-sanitized')
   run([out/'api-sanitized',valid['stereo'][0],valid['stereo'][2],valid['stereo'][1],out],'api-sanitized')
   for name,status in [('bad-crc',5),('truncated',5),('chained',5),('allocation-budget',12)]:
    p=out/(name+'.bin');window((p,29,p.stat().st_size-29-len(b'outside-record-never-read')),0,1,status,out/'window-sanitized')
  report['passed']=True
 except Exception as error:report['passed']=False;report['error']=str(error)
 after={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()for p in src};after.update({'native-audio/'+k:v for k,v in build.source_hashes().items()});report['sourceUnchanged']=before==after;report['sourceHashes']=after;report['passed']=report['passed']and before==after
 (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':len(report['checks']),'work':str(out),'error':report.get('error')}));return 0 if report['passed'] else 1
if __name__=='__main__':sys.exit(main())
