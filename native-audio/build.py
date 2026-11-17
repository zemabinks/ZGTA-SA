#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Build the pinned native radio decoder into this checkout's private local-only.

No downloads/autotools/source generation. Vendor bytes are release-exact. Only
independent allocation compile-prefix and source-stamp macros configure the code.
"""
from pathlib import Path
import argparse,hashlib,json,os,platform,shutil,subprocess,tempfile,time
ROOT=Path(__file__).resolve().parent
PROJECT=ROOT.parent
COMMON='mdct smallft block envelope window lsp lpc analysis synthesis psy info floor1 floor0 res0 mapping0 registry codebook sharedbook lookup bitrate vorbisfile'.split()
TARGETS={
 'macos-x86_64':('macosx','x86_64-apple-macosx12.0'),
 'macos-arm64':('macosx','arm64-apple-macosx12.0'),
 'ios-arm64':('iphoneos','arm64-apple-ios15.0'),
 'ios-simulator-arm64':('iphonesimulator','arm64-apple-ios15.0-simulator'),
 'ios-simulator-x86_64':('iphonesimulator','x86_64-apple-ios15.0-simulator')}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def check_regular(p):
 if p.is_symlink()or not p.is_file():raise ValueError('Expected non-linked source: '+str(p))
 for parent in p.parents:
  if parent.is_symlink():raise ValueError('Linked source parent: '+str(parent))
  if parent==PROJECT:break
def source_hashes():
 provenance=ROOT/'vendor/provenance.json';check_regular(provenance);data=json.loads(provenance.read_text());expected={'provenance.json'}
 for package in data['packages']:
  for item in package['upstreamFiles']:
   p=ROOT/item['path'];check_regular(p)
   if p.stat().st_size!=item['bytes']or sha(p)!=item['sha256']:raise ValueError('Pinned upstream source changed: '+item['path'])
   expected.add(str(p.relative_to(ROOT/'vendor')))
 for p in (ROOT/'vendor').rglob('*'):
  if p.is_symlink():raise ValueError('Linked vendor source: '+str(p))
  if p.is_file()and str(p.relative_to(ROOT/'vendor'))not in expected:raise ValueError('Unexpected vendor file: '+str(p))
 names=[ROOT/'build.py',provenance,*sorted((ROOT/'include').glob('*')),*sorted((ROOT/'src').glob('*')),*sorted((ROOT/'patches').glob('*.json'))]
 names += [ROOT/i['path']for pkg in data['packages']for i in pkg['upstreamFiles']]
 for p in names:check_regular(p)
 return {str(p.relative_to(ROOT)):sha(p)for p in names}
def compile_source(source,stage,applied):
 # Keep release/vendor bytes exact; compile this narrowly pinned upstream fix
 # in private output. There is no sanitizer exemption or floating-point change.
 spec=ROOT/'patches/vorbis-sharedbook-unsigned.json';check_regular(spec)
 patch=json.loads(spec.read_text())
 if str(source.relative_to(ROOT))!=patch['path']:return source
 original=source.read_bytes();before=patch['before'].encode();after=patch['after'].encode()
 if patch['schema']!=1 or hashlib.sha256(original).hexdigest()!=patch['originalSHA256'] or original.count(before)!=1:
  raise ValueError('Pinned upstream compatibility patch base mismatch')
 transformed=original.replace(before,after)
 if hashlib.sha256(transformed).hexdigest()!=patch['patchedSHA256']:raise ValueError('Pinned upstream compatibility patch output mismatch')
 output=stage/(source.stem+'-upstream.c');output.write_bytes(transformed)
 applied.append({key:patch[key]for key in ['path','originalSHA256','patchedSHA256','upstreamCommit','upstreamURL']})
 return output
def private_output(path):
 p=Path(os.path.abspath(path));base=PROJECT/'local-only'
 if not p.is_relative_to(base)or p==base:raise ValueError('Build output must be beneath this checkout local-only')
 for node in [p,*p.parents]:
  if node.is_symlink():raise ValueError('Refusing linked output/parent: '+str(node))
  if node==PROJECT:break
 return p
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,default=PROJECT/'local-only/native-audio');parser.add_argument('--platform',action='append',choices=[*TARGETS,'host','all']);parser.add_argument('--sanitize',action='store_true');args=parser.parse_args()
 before=source_hashes();stamp=hashlib.sha256(json.dumps(before,sort_keys=True,separators=(',',':')).encode()).hexdigest()
 selected=args.platform or ['host'];host='macos-arm64'if platform.machine()=='arm64'else'macos-x86_64'
 selected=list(dict.fromkeys(t for value in selected for t in (list(TARGETS)if value=='all'else[host if value=='host'else value])))
 if args.sanitize and selected!=[host]:raise ValueError('Sanitizer execution build is host-only')
 out=private_output(args.output);out.mkdir(parents=True,exist_ok=True);private_output(out)
 for name in selected:
  sdk,target=TARGETS[name];sdkpath=subprocess.check_output(['xcrun','--sdk',sdk,'--show-sdk-path'],text=True).strip()
  stage=Path(tempfile.mkdtemp(prefix='.audio-build-',dir=out));started=time.time()
  try:
   includes=['-I'+str(ROOT/'include'),'-I'+str(ROOT/'vendor/libogg-1.3.6/include'),'-I'+str(ROOT/'vendor/libvorbis-1.3.7/include'),'-I'+str(ROOT/'vendor/libvorbis-1.3.7/lib')]
   flags=['-target',target,'-isysroot',sdkpath,'-std=gnu11','-O2','-fvisibility=hidden','-ffp-contract=off','-fno-fast-math','-ffunction-sections','-fdata-sections',*includes]
   if args.sanitize:flags+=['-fsanitize=address,undefined','-fno-omit-frame-pointer','-g']
   sources=[ROOT/'src/zgtasa_native_audio.c',*[ROOT/('vendor/libogg-1.3.6/src/'+n+'.c')for n in ['bitwise','framing']],*[ROOT/('vendor/libvorbis-1.3.7/lib/'+n+'.c')for n in COMMON]]
   objects=[];applied=[]
   for index,source in enumerate(sources):
    obj=stage/(str(index)+'-'+source.stem+'.o');command=['xcrun','clang',*flags]
    if index:command+=['-include',str(ROOT/'src/codec_alloc.h'),'-Wno-parentheses','-Wno-shift-negative-value']
    else:command+=['-Wall','-Wextra','-Werror','-DZGTA_RADIO_SOURCE_STAMP="'+stamp+'"']
    compiled=compile_source(source,stage,applied)
    subprocess.run([*command,'-c',str(compiled),'-o',str(obj)],check=True);objects.append(obj)
   archive=stage/'libzgtasa_native_audio.a';subprocess.run(['xcrun','ar','rcs',str(archive),*map(str,objects)],check=True)
   probe=stage/'link.c';probe.write_text('#include "zgtasa_native_audio.h"\n#include <string.h>\nint main(void){zgta_radio_decoder*d=0;zgta_radio_info i;zgta_radio_stats s;float out[2];uint32_t n;zgta_radio_create(-1,0,0,&d);zgta_radio_prepare(d,&i);zgta_radio_read(d,0,1,out,2,&n);zgta_radio_get_stats(d,&s);zgta_radio_cancel(d);zgta_radio_destroy(d);return strcmp(zgta_radio_source_stamp(),"'+stamp+'");}\n')
   command=['xcrun','clang',*flags,str(probe),str(archive),'-lm','-Wl,-dead_strip','-o',str(stage/'link-probe')]
   subprocess.run(command,check=True)
   if source_hashes()!=before:raise ValueError('Native audio sources changed while building')
   destination=private_output(out/name);destination.mkdir(exist_ok=True)
   for artifact in ['libzgtasa_native_audio.a','link-probe']:
    if (destination/artifact).is_symlink():raise ValueError('Refusing linked build artifact')
    os.replace(stage/artifact,destination/artifact)
   report={'schema':1,'target':target,'sdk':sdkpath,'sourceStamp':stamp,'sourceHashes':before,'librarySHA256':sha(destination/'libzgtasa_native_audio.a'),'linkProbeSHA256':sha(destination/'link-probe'),'sanitizers':args.sanitize,'upstreamCompatibilityPatches':applied,'elapsedSeconds':time.time()-started,'sourceUnchanged':True,'runtimeExecuted':False}
   metadata=stage/'source-stamp.json';metadata.write_text(json.dumps(report,indent=2)+'\n');os.replace(metadata,destination/'source-stamp.json')
   print(json.dumps({'platform':name,'sourceStamp':stamp,'library':str(destination/'libzgtasa_native_audio.a'),'compileLink':'PASS','sanitizers':args.sanitize}),flush=True)
  finally:shutil.rmtree(stage)
if __name__=='__main__':main()
